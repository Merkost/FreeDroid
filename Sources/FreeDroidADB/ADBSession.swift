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

    private static let wireEnabled = UserDefaults.standard.bool(forKey: "freedroid.useWireClient")

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

    public func list(_ path: RemotePath) async throws -> [RemoteEntry] {
        if Self.wireEnabled {
            return try await wireList(path)
        }
        return try await legacyList(path)
    }

    private func wireList(_ path: RemotePath) async throws -> [RemoteEntry] {
        let syncClient = try await ADBSyncClient.open(serial: serial, host: wireHost, port: wirePort)
        defer { syncClient.close() }
        let entries = try await syncClient.listV2(remotePath: path.raw)
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

    private func legacyList(_ path: RemotePath) async throws -> [RemoteEntry] {
        let runner = await server.runner(for: serial)
        let out = try await runner.run(
            .shell(serial: serial, script: "ls -alL --time-style=long-iso \(escape(path.raw))/"),
            timeout: .seconds(15)
        )
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
                modifiedAt: nil,
                isHidden: parsed.name.hasPrefix(".")
            )
        }
    }

    public func stat(_ path: RemotePath) async throws -> RemoteEntry {
        if Self.wireEnabled {
            return try await wireStat(path)
        }
        return try await legacyStat(path)
    }

    private func wireStat(_ path: RemotePath) async throws -> RemoteEntry {
        let syncClient = try await ADBSyncClient.open(serial: serial, host: wireHost, port: wirePort)
        defer { syncClient.close() }
        let entry = try await syncClient.statV2(remotePath: path.raw)
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
        let parent = path.parent ?? .root
        let entries = try await legacyList(parent)
        guard let match = entries.first(where: { $0.name == path.name }) else {
            throw TransportError.notFound(path)
        }
        return match
    }

    public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        if Self.wireEnabled {
            return try await wireRead(path, offset: offset, length: length)
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
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.pull(serial: serial, remote: path.raw, local: temp.path), timeout: .seconds(120))
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
            try await wireWrite(path, data: data)
        } else {
            try await legacyWrite(path, data: data)
        }
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
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.push(serial: serial, local: temp.path, remote: path.raw), timeout: .seconds(300))
    }

    public func mkdir(_ path: RemotePath) async throws {
        if Self.wireEnabled {
            let shell = ADBShellClient(host: wireHost, port: wirePort)
            let result = try await shell.run(serial: serial, command: "mkdir -p \(escape(path.raw))")
            guard result.exitCode == 0 else {
                throw TransportError.ioFailure(message: result.stderr)
            }
        } else {
            let runner = await server.runner(for: serial)
            _ = try await runner.run(.shell(serial: serial, script: "mkdir -p \(escape(path.raw))"), timeout: .seconds(5))
        }
    }

    public func remove(_ path: RemotePath) async throws {
        if Self.wireEnabled {
            let shell = ADBShellClient(host: wireHost, port: wirePort)
            let result = try await shell.run(serial: serial, command: "rm -rf \(escape(path.raw))")
            guard result.exitCode == 0 else {
                throw TransportError.ioFailure(message: result.stderr)
            }
        } else {
            let runner = await server.runner(for: serial)
            _ = try await runner.run(.shell(serial: serial, script: "rm -rf \(escape(path.raw))"), timeout: .seconds(30))
        }
    }

    public func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        if Self.wireEnabled {
            let shell = ADBShellClient(host: wireHost, port: wirePort)
            let result = try await shell.run(serial: serial, command: "mv \(escape(from.raw)) \(escape(destination.raw))")
            guard result.exitCode == 0 else {
                throw TransportError.ioFailure(message: result.stderr)
            }
        } else {
            let runner = await server.runner(for: serial)
            _ = try await runner.run(
                .shell(serial: serial, script: "mv \(escape(from.raw)) \(escape(destination.raw))"),
                timeout: .seconds(30)
            )
        }
    }

    public func close() async {
        cachedInfo = nil
    }

    private func escape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
