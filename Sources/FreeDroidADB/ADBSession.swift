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
    private var cachedInfo: DeviceInfo?

    public init(deviceID: DeviceID, serial: String, server: ADBServer) {
        self.deviceID = deviceID
        self.serial = serial
        self.server = server
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
        let runner = await server.runner(for: serial)
        let out = try await runner.run(
            .shell(serial: serial, script: "ls -alL \(escape(path.raw))/"),
            timeout: .seconds(45)
        )
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

    public func stat(_ path: RemotePath) async throws -> RemoteEntry {
        let parent = path.parent ?? .root
        let entries = try await list(parent)
        guard let match = entries.first(where: { $0.name == path.name }) else {
            throw TransportError.notFound(path)
        }
        return match
    }

    public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
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
        let temp = ADBFileSync.tempLocalPath()
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.push(serial: serial, local: temp.path, remote: path.raw), timeout: .seconds(300))
    }

    public func mkdir(_ path: RemotePath) async throws {
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: "mkdir -p \(escape(path.raw))"), timeout: .seconds(5))
    }

    public func remove(_ path: RemotePath) async throws {
        let runner = await server.runner(for: serial)
        _ = try await runner.run(.shell(serial: serial, script: "rm -rf \(escape(path.raw))"), timeout: .seconds(30))
    }

    public func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        let runner = await server.runner(for: serial)
        _ = try await runner.run(
            .shell(serial: serial, script: "mv \(escape(from.raw)) \(escape(destination.raw))"),
            timeout: .seconds(30)
        )
    }

    public func close() async {
        cachedInfo = nil
    }

    private func escape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
