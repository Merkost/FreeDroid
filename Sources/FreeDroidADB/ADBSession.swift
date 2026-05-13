import Foundation
import os
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
    private lazy var syncPool = ADBSyncConnectionPool(serial: serial, host: wireHost, port: wirePort)

    private static var wireEnabled: Bool {
        let suite = UserDefaults(suiteName: "group.com.merkost.freedroid") ?? .standard
        let key = "freedroid.useWireClient"
        if suite.object(forKey: key) == nil { return true }
        return suite.bool(forKey: key)
    }

    private static let lastFallbackLog = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

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
            async let storage = readStorageStats(runner: runner)
            let stats = await storage
            let info = DeviceInfo(
                serial: serial,
                manufacturer: try await manufacturer,
                model: try await model,
                androidVersion: try await version,
                storageCapacityBytes: stats?.capacity,
                storageFreeBytes: stats?.free
            )
            cachedInfo = info
            return info
        }
    }

    private func readStorageStats(runner: any ADBRunner) async -> (capacity: Int64, free: Int64)? {
        guard let out = try? await runner.run(
            .shell(serial: serial, script: "df /sdcard"),
            timeout: .seconds(3)
        ) else { return nil }
        let lines = out.stdout.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return nil }
        let cols = lines[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard cols.count >= 4, let totalK = Int64(cols[1]), let freeK = Int64(cols[3]) else { return nil }
        return (capacity: totalK * 1024, free: freeK * 1024)
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
        try await withWireFallback(op: "list", path: path.raw) {
            try await self.wireList(path)
        } legacy: {
            try await self.legacyList(path)
        }
    }

    public func stat(_ path: RemotePath) async throws -> RemoteEntry {
        let key = path.raw
        if let existing = inFlightStats[key] {
            return try await existing.value
        }
        let task = Task { [self] in
            try await withWireFallback(op: "stat", path: key) {
                try await self.wireStat(path)
            } legacy: {
                try await self.legacyStat(path)
            }
        }
        inFlightStats[key] = task
        defer { inFlightStats[key] = nil }
        return try await task.value
    }

    public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        try await withWireFallback(op: "read", path: path.raw) {
            try await self.wireRead(path, offset: offset, length: length)
        } legacy: {
            try await self.legacyRead(path, offset: offset, length: length)
        }
    }

    public func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
        guard offset == 0 else {
            throw TransportError.unsupported(reason: "ADB push does not support offset writes")
        }
        try await withWireFallback(op: "write", path: path.raw) {
            try await self.wireWrite(path, data: data)
        } legacy: {
            try await self.legacyWrite(path, data: data)
        }
    }

    public func mkdir(_ path: RemotePath) async throws {
        try await runShell(op: "mkdir", command: "mkdir -p \(escape(path.raw))", legacyTimeout: .seconds(5))
    }

    public func remove(_ path: RemotePath) async throws {
        try await runShell(op: "remove", command: "rm -rf \(escape(path.raw))", legacyTimeout: .seconds(30))
    }

    public func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        try await runShell(
            op: "rename",
            command: "mv \(escape(from.raw)) \(escape(destination.raw))",
            legacyTimeout: .seconds(30)
        )
    }

    public func fetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64 {
        try await withWireFallback(op: "fetch", path: path.raw) {
            try await self.wireFetch(path, into: destination, progress: progress)
        } legacy: {
            try await self.legacyFetch(path, into: destination, progress: progress)
        }
    }

    public func upload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64 {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw TransportError.notFound(RemotePath(raw: source.path))
        }
        let bytes = try await withWireFallback(op: "upload", path: path.raw) {
            try await self.wireUpload(from: source, to: path, progress: progress)
        } legacy: {
            try await self.legacyUpload(from: source, to: path, progress: progress)
        }
        await rescanMediaStore(path: path)
        return bytes
    }

    private func legacyFetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64 {
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

    private func legacyUpload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64 {
        let runner = await server.runner(for: serial)
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        let compressed = await zstdEnabled()
        _ = try await runner.run(
            .push(serial: serial, local: source.path, remote: path.raw, compressed: compressed),
            timeout: .seconds(600)
        )
        progress?(size, size)
        return size
    }

    public func close() async {
        cachedInfo = nil
        cachedZstd = nil
        cachedDeviceFeatures = nil
        await syncPool.drain()
    }

    private func withWireFallback<T: Sendable>(
        op: String,
        path: String,
        wire: () async throws -> T,
        legacy: () async throws -> T
    ) async throws -> T {
        if Self.wireEnabled {
            do {
                return try await wire()
            } catch let error as TransportError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.logFallback(op: op, path: path, error: error)
            }
        }
        return try await legacy()
    }

    private func runShell(op: String, command: String, legacyTimeout: Duration) async throws {
        try await withWireFallback(op: op, path: command) {
            try await self.wireShell(command)
        } legacy: {
            try await self.legacyShell(command, timeout: legacyTimeout)
        }
    }

    private func wireShell(_ command: String) async throws {
        let shell = ADBShellClient(host: wireHost, port: wirePort, features: await deviceFeatures())
        let result = try await shell.run(serial: serial, command: command)
        guard result.exitCode == 0 else {
            throw TransportError.ioFailure(message: result.stderr)
        }
    }

    private func legacyShell(_ command: String, timeout: Duration) async throws {
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: command), timeout: timeout)
    }

    private static func logFallback(op: String, path: String, error: Error) {
        let now = Date().timeIntervalSince1970
        let shouldLog = lastFallbackLog.withLock { last -> Bool in
            if now - last < 30 { return false }
            last = now
            return true
        }
        guard shouldLog else { return }
        Swift.print("[FreeDroid] wire \(op) failed for \(path), falling back to legacy: \(error)")
    }

    private func wireList(_ path: RemotePath) async throws -> [RemoteEntry] {
        let feats = await deviceFeatures()
        let entries = try await syncPool.withConnection { syncClient -> [SyncEntry] in
            if feats.contains("ls_v2") {
                return try await syncClient.listV2(remotePath: path.raw)
            }
            return try await syncClient.listV1(remotePath: path.raw)
        }
        return entries.map { entry in
            let kind: EntryKind = entry.isDirectory ? .directory : (entry.isSymlink ? .symlink : .file)
            return RemoteEntry(
                path: path.appending(entry.name),
                name: entry.name,
                kind: kind,
                sizeBytes: entry.isDirectory ? nil : Int64(bitPattern: entry.size),
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(entry.mtime)),
                isHidden: entry.name.hasPrefix(".")
            )
        }
    }

    private func wireStat(_ path: RemotePath) async throws -> RemoteEntry {
        let feats = await deviceFeatures()
        let entry = try await syncPool.withConnection { syncClient -> SyncEntry in
            if feats.contains("stat_v2") {
                return try await syncClient.statV2(remotePath: path.raw)
            }
            return try await syncClient.statV1(remotePath: path.raw)
        }
        let kind: EntryKind = entry.isDirectory ? .directory : (entry.isSymlink ? .symlink : .file)
        return RemoteEntry(
            path: path,
            name: path.name,
            kind: kind,
            sizeBytes: entry.isDirectory ? nil : Int64(bitPattern: entry.size),
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(entry.mtime)),
            isHidden: path.name.hasPrefix(".")
        )
    }

    private func wireRead(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        let temp = ADBFileSync.tempLocalPath()
        defer { try? FileManager.default.removeItem(at: temp) }
        try await syncPool.withConnection { syncClient in
            _ = try await syncClient.recv(remotePath: path.raw, to: temp, progress: nil)
        }
        return try Self.sliceData(at: temp, offset: offset, length: length)
    }

    private func wireWrite(_ path: RemotePath, data: Data) async throws {
        let temp = ADBFileSync.tempLocalPath()
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        try await syncPool.withConnection { syncClient in
            _ = try await syncClient.send(from: temp, remotePath: path.raw)
        }
    }

    private func wireFetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64 {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        return try await syncPool.withConnection { syncClient in
            try await syncClient.recv(remotePath: path.raw, to: destination, progress: progress)
        }
    }

    private func wireUpload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64 {
        try await syncPool.withConnection { syncClient in
            try await syncClient.send(from: source, remotePath: path.raw, progress: progress)
        }
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
            return RemoteEntry(
                path: path.appending(parsed.name),
                name: parsed.name,
                kind: parsed.isDirectory ? .directory : .file,
                sizeBytes: parsed.isDirectory ? nil : parsed.size,
                modifiedAt: Self.modifiedAtFormatter.date(from: parsed.modifiedAt),
                isHidden: parsed.name.hasPrefix(".")
            )
        }
    }

    private func legacyStat(_ path: RemotePath) async throws -> RemoteEntry {
        let runner = await server.runner(for: serial)
        let out: ADBProcessOutput
        do {
            out = try await runner.run(
                .shell(serial: serial, script: "stat -c '%F|%s|%Y' \(escape(path.raw))"),
                timeout: .seconds(5)
            )
        } catch let ADBRunnerError.nonZeroExit(_, stderr) where Self.isInaccessible(stderr) {
            throw TransportError.notFound(path)
        }
        let parts = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return try await legacyStatViaList(path) }
        let kind = Self.parseStatKind(String(parts[0]))
        let size = Int64(parts[1].trimmingCharacters(in: .whitespaces))
        let mtime = TimeInterval(parts[2].trimmingCharacters(in: .whitespaces))
        return RemoteEntry(
            path: path,
            name: path.name,
            kind: kind,
            sizeBytes: kind == .directory ? nil : size,
            modifiedAt: mtime.map(Date.init(timeIntervalSince1970:)),
            isHidden: path.name.hasPrefix(".")
        )
    }

    private static func parseStatKind(_ raw: String) -> EntryKind {
        let lowered = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if lowered.contains("directory") { return .directory }
        if lowered.contains("symbolic") { return .symlink }
        return .file
    }

    private func legacyStatViaList(_ path: RemotePath) async throws -> RemoteEntry {
        let parent = path.parent ?? .root
        let entries = try await legacyList(parent)
        guard let match = entries.first(where: { $0.name == path.name }) else {
            throw TransportError.notFound(path)
        }
        return match
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
        return try Self.sliceData(at: temp, offset: offset, length: length)
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

    private static func sliceData(at url: URL, offset: Int64, length: Int) throws -> Data {
        let data = try Data(contentsOf: url)
        let start = Int(offset)
        guard start < data.count else { return Data() }
        let end = min(start + length, data.count)
        return data.subdata(in: start..<end)
    }

    private static func isInaccessible(_ stderr: String) -> Bool {
        let lowered = stderr.lowercased()
        return lowered.contains("permission denied")
            || lowered.contains("operation not permitted")
            || lowered.contains("no such file or directory")
    }

    private func deviceFeatures() async -> Set<String> {
        if let cached = cachedDeviceFeatures { return cached }
        let host = ADBHostClient(host: wireHost, port: wirePort)
        let list = (try? await host.features(serial: serial)) ?? []
        let set = Set(list)
        cachedDeviceFeatures = set
        return set
    }

    private func zstdEnabled() async -> Bool {
        if let cached = cachedZstd { return cached }
        let result = (try? await server.features()) ?? []
        let enabled = result.contains("zstd_decompress") && result.contains("zstd_compress")
        cachedZstd = enabled
        return enabled
    }

    private func rescanMediaStore(path: RemotePath) async {
        let runner = await server.runner(for: serial)
        let script = "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d 'file://\(path.raw)'"
        _ = try? await runner.run(.shell(serial: serial, script: script), timeout: .seconds(5))
    }

    private func escape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
