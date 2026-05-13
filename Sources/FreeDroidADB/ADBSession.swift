import Foundation
import FreeDroidDomain

public actor ADBSession: Transport {
    public let deviceID: DeviceID
    public let capabilities = TransportCapabilities(
        supportsRangeRead: false,
        supportsRangeWrite: false,
        supportsSymlinks: true,
        recommendedChunkBytes: 1 << 20
    )

    private let serial: String
    private let server: ADBServer
    private let wireHost: String
    private let wirePort: UInt16
    private var cachedInfo: DeviceInfo?
    private var cachedZstd: Bool?
    private var cachedDeviceFeatures: Set<String>?
    private var inFlightStats: [String: Task<RemoteEntry, Error>] = [:]

    private static var wireEnabled: Bool {
        let suite = UserDefaults(suiteName: "group.com.merkost.freedroid") ?? .standard
        let key = "freedroid.useWireClient"
        if suite.object(forKey: key) == nil { return true }
        return suite.bool(forKey: key)
    }

    public init(deviceID: DeviceID, serial: String, server: ADBServer, wireHost: String = "127.0.0.1", wirePort: UInt16 = 5037) {
        self.deviceID = deviceID
        self.serial = serial
        self.server = server
        self.wireHost = wireHost
        self.wirePort = wirePort
    }

    public var info: DeviceInfo {
        get async throws {
            if let cachedInfo { return cachedInfo }
            let runner = await server.runner(for: serial)
            async let manufacturer = property(runner: runner, key: "ro.product.manufacturer")
            async let model = property(runner: runner, key: "ro.product.model")
            async let version = property(runner: runner, key: "ro.build.version.release")
            let info = DeviceInfo(
                serial: serial,
                manufacturer: try await manufacturer,
                model: try await model,
                androidVersion: try await version,
                storageCapacityBytes: nil,
                storageFreeBytes: nil
            )
            cachedInfo = info
            return info
        }
    }

    private func property(runner: any ADBRunner, key: String) async throws -> String {
        let out = try await runner.run(.getProp(serial: serial, property: key), timeout: .seconds(5))
        return out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let modifiedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public func list(_ path: RemotePath) async throws -> [RemoteEntry] {
        if Self.wireEnabled {
            do {
                return try await wireList(path)
            } catch let error as ADBWireError {
                wireFallbackLogger("list", path: path.raw, error: error)
                return try await legacyList(path)
            }
        }
        return try await legacyList(path)
    }

    private nonisolated func wireFallbackLogger(_ op: String, path: String, error: Error) {
        let suite = UserDefaults(suiteName: "group.com.merkost.freedroid") ?? .standard
        let key = "freedroid.wireFallbackLogged"
        let last = suite.double(forKey: key)
        let now = Date().timeIntervalSince1970
        if now - last < 30 { return }
        suite.set(now, forKey: key)
        Swift.print("[FreeDroid] wire \(op) failed for \(path), falling back to legacy: \(error)")
    }

    private func wireList(_ path: RemotePath) async throws -> [RemoteEntry] {
        let feats = await deviceFeatures()
        let syncClient = try await ADBSyncClient.open(serial: serial, host: wireHost, port: wirePort)
        defer { syncClient.close() }
        let entries: [SyncEntry]
        if feats.contains("ls_v2") {
            entries = try await syncClient.listV2(remotePath: path.raw)
        } else {
            entries = try await syncClient.listV1(remotePath: path.raw)
        }
        return entries.map { entry in
            let kind: EntryKind = entry.isDirectory ? .directory : (entry.isSymlink ? .symlink : .file)
            let modifiedAt = Date(timeIntervalSince1970: TimeInterval(entry.mtime))
            return RemoteEntry(
                path: path.appending(entry.name),
                name: entry.name,
                kind: kind,
                sizeBytes: entry.isDirectory ? nil : Int64(bitPattern: entry.size),
                modifiedAt: modifiedAt,
                isHidden: entry.name.hasPrefix(".")
            )
        }
    }

    private func deviceFeatures() async -> Set<String> {
        if let cached = cachedDeviceFeatures { return cached }
        let host = ADBHostClient(host: wireHost, port: wirePort)
        let list = (try? await host.features(serial: serial)) ?? []
        let set = Set(list)
        cachedDeviceFeatures = set
        return set
    }

    private func legacyList(_ path: RemotePath) async throws -> [RemoteEntry] {
        let runner = await server.runner(for: serial)
        let out: ADBProcessOutput
        do {
            out = try await runner.run(
                .shell(serial: serial, script: "ls -alL \(escape(path.raw))/"),
                timeout: .seconds(45)
            )
        } catch let ADBRunnerError.nonZeroExit(_, stderr) where Self.isInaccessible(stderr) {
            return []
        }
        if Self.isInaccessible(out.stderr) { return [] }
        let lines = out.stdout.split(separator: "\n").map(String.init)
        return lines.compactMap { line -> RemoteEntry? in
            guard !line.hasPrefix("total ") else { return nil }
            guard let parsed = ADBOutputParser.parseLsLine(line) else { return nil }
            guard parsed.name != "." && parsed.name != ".." else { return nil }
            let modifiedAt = Self.modifiedAtFormatter.date(from: parsed.modifiedAt)
            return RemoteEntry(
                path: path.appending(parsed.name),
                name: parsed.name,
                kind: parsed.isDirectory ? .directory : .file,
                sizeBytes: parsed.isDirectory ? nil : parsed.size,
                modifiedAt: modifiedAt,
                isHidden: parsed.name.hasPrefix(".")
            )
        }
    }

    private static func isInaccessible(_ stderr: String) -> Bool {
        let lowered = stderr.lowercased()
        return lowered.contains("permission denied")
            || lowered.contains("operation not permitted")
            || lowered.contains("no such file or directory")
    }

    public func stat(_ path: RemotePath) async throws -> RemoteEntry {
        let key = path.raw
        if let existing = inFlightStats[key] {
            return try await existing.value
        }
        let task = Task { [self] in
            try await statWithFallback(path)
        }
        inFlightStats[key] = task
        defer { inFlightStats[key] = nil }
        return try await task.value
    }

    private func statWithFallback(_ path: RemotePath) async throws -> RemoteEntry {
        if Self.wireEnabled {
            do {
                return try await wireStat(path)
            } catch let error as ADBWireError {
                wireFallbackLogger("stat", path: path.raw, error: error)
                return try await legacyStat(path)
            }
        }
        return try await legacyStat(path)
    }

    private func wireStat(_ path: RemotePath) async throws -> RemoteEntry {
        let feats = await deviceFeatures()
        let syncClient = try await ADBSyncClient.open(serial: serial, host: wireHost, port: wirePort)
        defer { syncClient.close() }
        let entry: SyncEntry
        if feats.contains("stat_v2") {
            entry = try await syncClient.statV2(remotePath: path.raw)
        } else {
            entry = try await syncClient.statV1(remotePath: path.raw)
        }
        let kind: EntryKind = entry.isDirectory ? .directory : (entry.isSymlink ? .symlink : .file)
        let modifiedAt = Date(timeIntervalSince1970: TimeInterval(entry.mtime))
        return RemoteEntry(
            path: path,
            name: path.name,
            kind: kind,
            sizeBytes: entry.isDirectory ? nil : Int64(bitPattern: entry.size),
            modifiedAt: modifiedAt,
            isHidden: path.name.hasPrefix(".")
        )
    }

    private func legacyStat(_ path: RemotePath) async throws -> RemoteEntry {
        let runner = await server.runner(for: serial)
        let script = "stat -c '%F|%s|%Y' \(escape(path.raw))"
        let out: ADBProcessOutput
        do {
            out = try await runner.run(.shell(serial: serial, script: script), timeout: .seconds(5))
        } catch let ADBRunnerError.nonZeroExit(_, stderr) where Self.isInaccessible(stderr) {
            throw TransportError.notFound(path)
        }
        let trimmed = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else {
            return try await legacyStatViaList(path)
        }
        let typeRaw = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let size = Int64(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        let mtimeUnix = TimeInterval(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0
        let kind: EntryKind
        if typeRaw.contains("directory") {
            kind = .directory
        } else if typeRaw.contains("symbolic") {
            kind = .symlink
        } else {
            kind = .file
        }
        return RemoteEntry(
            path: path,
            name: path.name,
            kind: kind,
            sizeBytes: kind == .directory ? nil : size,
            modifiedAt: Date(timeIntervalSince1970: mtimeUnix),
            isHidden: path.name.hasPrefix(".")
        )
    }

    private func legacyStatViaList(_ path: RemotePath) async throws -> RemoteEntry {
        let parent = path.parent ?? .root
        let entries = try await legacyList(parent)
        guard let match = entries.first(where: { $0.name == path.name }) else {
            throw TransportError.notFound(path)
        }
        return match
    }

    public func fetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64 {
        let runner = await server.runner(for: serial)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        let compressed = await zstdEnabled()
        _ = try await runner.run(
            .pull(serial: serial, remote: path.raw, local: destination.path, compressed: compressed),
            timeout: .seconds(600)
        )
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        progress?(size, size)
        return size
    }

    public func upload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64 {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw TransportError.notFound(RemotePath(raw: source.path))
        }
        let runner = await server.runner(for: serial)
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        let compressed = await zstdEnabled()
        _ = try await runner.run(
            .push(serial: serial, local: source.path, remote: path.raw, compressed: compressed),
            timeout: .seconds(600)
        )
        await rescanMediaStore(path: path)
        progress?(size, size)
        return size
    }

    private func rescanMediaStore(path: RemotePath) async {
        let runner = await server.runner(for: serial)
        let script = "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d 'file://\(path.raw)'"
        _ = try? await runner.run(.shell(serial: serial, script: script), timeout: .seconds(5))
    }

    public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        if Self.wireEnabled {
            do {
                return try await wireRead(path, offset: offset, length: length)
            } catch let error as ADBWireError {
                wireFallbackLogger("read", path: path.raw, error: error)
                return try await legacyRead(path, offset: offset, length: length)
            }
        }
        return try await legacyRead(path, offset: offset, length: length)
    }

    private func wireRead(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        let temp = ADBFileSync.tempLocalPath()
        defer { try? FileManager.default.removeItem(at: temp) }
        let syncClient = try await ADBSyncClient.open(serial: serial, host: wireHost, port: wirePort)
        defer { syncClient.close() }
        _ = try await syncClient.recv(remotePath: path.raw, to: temp, progress: nil)
        let data = try Data(contentsOf: temp)
        let start = Int(offset)
        let end = min(start + length, data.count)
        guard start < data.count else { return Data() }
        return data.subdata(in: start..<end)
    }

    private func legacyRead(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        let temp = ADBFileSync.tempLocalPath()
        defer { try? FileManager.default.removeItem(at: temp) }
        let compressed = await zstdEnabled()
        let runner = await server.runner(for: serial)
        _ = try await runner.run(
            .pull(serial: serial, remote: path.raw, local: temp.path, compressed: compressed),
            timeout: .seconds(120)
        )
        let data = try Data(contentsOf: temp)
        let start = Int(offset)
        let end = min(start + length, data.count)
        guard start < data.count else { return Data() }
        return data.subdata(in: start..<end)
    }

    public func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
        guard offset == 0 else {
            throw TransportError.unsupported(reason: "ADB push does not support offset writes")
        }
        if Self.wireEnabled {
            do {
                try await wireWrite(path, data: data)
                return
            } catch let error as ADBWireError {
                wireFallbackLogger("write", path: path.raw, error: error)
            }
        }
        try await legacyWrite(path, data: data)
    }

    private func wireWrite(_ path: RemotePath, data: Data) async throws {
        let temp = ADBFileSync.tempLocalPath()
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let syncClient = try await ADBSyncClient.open(serial: serial, host: wireHost, port: wirePort)
        defer { syncClient.close() }
        _ = try await syncClient.send(from: temp, remotePath: path.raw)
    }

    private func legacyWrite(_ path: RemotePath, data: Data) async throws {
        let temp = ADBFileSync.tempLocalPath()
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let compressed = await zstdEnabled()
        let runner = await server.runner(for: serial)
        _ = try await runner.run(
            .push(serial: serial, local: temp.path, remote: path.raw, compressed: compressed),
            timeout: .seconds(300)
        )
    }

    public func mkdir(_ path: RemotePath) async throws {
        if Self.wireEnabled {
            do {
                let shell = ADBShellClient(host: wireHost, port: wirePort, features: await deviceFeatures())
                let result = try await shell.run(serial: serial, command: "mkdir -p \(escape(path.raw))")
                guard result.exitCode == 0 else {
                    throw TransportError.ioFailure(message: result.stderr)
                }
                return
            } catch let error as ADBWireError {
                wireFallbackLogger("mkdir", path: path.raw, error: error)
            }
        }
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: "mkdir -p \(escape(path.raw))"), timeout: .seconds(5))
    }

    public func remove(_ path: RemotePath) async throws {
        if Self.wireEnabled {
            do {
                let shell = ADBShellClient(host: wireHost, port: wirePort, features: await deviceFeatures())
                let result = try await shell.run(serial: serial, command: "rm -rf \(escape(path.raw))")
                guard result.exitCode == 0 else {
                    throw TransportError.ioFailure(message: result.stderr)
                }
                return
            } catch let error as ADBWireError {
                wireFallbackLogger("remove", path: path.raw, error: error)
            }
        }
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: "rm -rf \(escape(path.raw))"), timeout: .seconds(30))
    }

    public func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        if Self.wireEnabled {
            do {
                let shell = ADBShellClient(host: wireHost, port: wirePort, features: await deviceFeatures())
                let result = try await shell.run(serial: serial, command: "mv \(escape(from.raw)) \(escape(destination.raw))")
                guard result.exitCode == 0 else {
                    throw TransportError.ioFailure(message: result.stderr)
                }
                return
            } catch let error as ADBWireError {
                wireFallbackLogger("rename", path: from.raw, error: error)
            }
        }
        let runner = await server.runner(for: serial)
        _ = try await runner.run(
            .shell(serial: serial, script: "mv \(escape(from.raw)) \(escape(destination.raw))"),
            timeout: .seconds(30)
        )
    }

    private func zstdEnabled() async -> Bool {
        if let cached = cachedZstd { return cached }
        let result = (try? await server.features()) ?? []
        let enabled = result.contains("zstd_decompress") && result.contains("zstd_compress")
        cachedZstd = enabled
        return enabled
    }

    public func close() async {
        cachedInfo = nil
        cachedZstd = nil
        cachedDeviceFeatures = nil
    }

    private func escape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
