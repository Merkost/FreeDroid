import Foundation
import os
import FreeDroidProviderShared

private struct ConnectionBox: @unchecked Sendable {
    var conn: NSXPCConnection?
}

final class ProviderTransport: @unchecked Sendable {
    let deviceID: DeviceID
    private let state = OSAllocatedUnfairLock<ConnectionBox>(initialState: ConnectionBox(conn: nil))

    init(deviceID: DeviceID) {
        self.deviceID = deviceID
    }

    func invalidate() async {
        state.withLock { box in
            box.conn?.invalidate()
            box.conn = nil
        }
    }

    func list(_ path: RemotePath) async throws -> [RemoteEntry] {
        try await send(.list(deviceID: deviceID, path: path), expecting: [RemoteEntry].self)
    }

    func stat(_ path: RemotePath) async throws -> RemoteEntry {
        try await send(.stat(deviceID: deviceID, path: path), expecting: RemoteEntry.self)
    }

    func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        try await send(
            .read(deviceID: deviceID, path: path, offset: offset, length: length),
            expecting: Data.self
        )
    }

    func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
        _ = try await send(
            .write(deviceID: deviceID, path: path, data: data, offset: offset),
            expecting: Data.self
        )
    }

    func mkdir(_ path: RemotePath) async throws {
        _ = try await send(.mkdir(deviceID: deviceID, path: path), expecting: Data.self)
    }

    func remove(_ path: RemotePath) async throws {
        _ = try await send(.remove(deviceID: deviceID, path: path), expecting: Data.self)
    }

    func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        _ = try await send(
            .rename(deviceID: deviceID, from: from, to: destination),
            expecting: Data.self
        )
    }

    func fetch(_ path: RemotePath, into destination: URL, progress: Progress? = nil) async throws {
        let sharedRoot = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.merkost.freedroid"
        ) ?? FileManager.default.temporaryDirectory
        let transferRoot = sharedRoot.appendingPathComponent("FreeDroidTransfers", isDirectory: true)
        try FileManager.default.createDirectory(at: transferRoot, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let staging = transferRoot.appendingPathComponent("fetch-\(token).data")
        let progressURL = transferRoot.appendingPathComponent("fetch-\(token).progress")
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: progressURL)
        }

        let request = Task {
            try await send(
                .fetchFile(
                    deviceID: deviceID,
                    path: path,
                    destinationPath: staging.path,
                    progressPath: progressURL.path
                ),
                expecting: Data.self
            )
        }
        let monitor = Task {
            while !Task.isCancelled {
            if let line = try? String(contentsOf: progressURL, encoding: .utf8) {
                let values = line.split(separator: "/").compactMap { Int64($0) }
                if let completed = values.first {
                    if values.count > 1, values[1] >= 0 { progress?.totalUnitCount = values[1] }
                    progress?.completedUnitCount = completed
                }
            }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer {
            monitor.cancel()
            if Task.isCancelled { request.cancel() }
        }
        _ = try await request.value

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: staging, to: destination)
    }

    func upload(from source: URL, to path: RemotePath, progress: Progress? = nil) async throws {
        let sharedRoot = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.merkost.freedroid"
        ) ?? FileManager.default.temporaryDirectory
        let transferRoot = sharedRoot.appendingPathComponent("FreeDroidTransfers", isDirectory: true)
        try FileManager.default.createDirectory(at: transferRoot, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let staging = transferRoot.appendingPathComponent("upload-\(token).data")
        let progressURL = transferRoot.appendingPathComponent("upload-\(token).progress")
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: progressURL)
        }
        try FileManager.default.copyItem(at: source, to: staging)
        progress?.isCancellable = true
        let request = Task {
            try await send(
                .uploadFile(
                    deviceID: deviceID,
                    path: path,
                    sourcePath: staging.path,
                    progressPath: progressURL.path
                ),
                expecting: Data.self
            )
        }
        let monitor = Task {
            while !Task.isCancelled {
                if let line = try? String(contentsOf: progressURL, encoding: .utf8) {
                    let values = line.split(separator: "/").compactMap { Int64($0) }
                    if let completed = values.first {
                        if values.count > 1, values[1] >= 0 { progress?.totalUnitCount = values[1] }
                        progress?.completedUnitCount = completed
                    }
                }
                if progress?.isCancelled == true {
                    request.cancel()
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer {
            monitor.cancel()
            if Task.isCancelled { request.cancel() }
        }
        _ = try await request.value
    }

    private func send<T: Decodable>(_ request: IPCRequest, expecting: T.Type) async throws -> T {
        let payload = try IPCCoder.encoder.encode(request)
        let proxy = makeProxy()
        let responseData = await proxy.send(payload)
        let response = try IPCCoder.decoder.decode(IPCResponse.self, from: responseData)
        switch response {
        case .entries(let entries) where T.self == [RemoteEntry].self:
            return entries as! T
        case .entry(let entry) where T.self == RemoteEntry.self:
            return entry as! T
        case .data(let data) where T.self == Data.self:
            return data as! T
        case .empty where T.self == Data.self:
            return Data() as! T
        case .failure(let ipcError):
            switch ipcError {
            case .transport(let e): throw e
            case .noTransport:      throw TransportError.notConnected
            case .decodingFailed(let m): throw TransportError.ioFailure(message: m)
            }
        default:
            throw TransportError.ioFailure(message: "Unexpected XPC response shape")
        }
    }

    private func makeProxy() -> any XPCFileServerProtocol {
        nonisolated(unsafe) var captured: NSXPCConnection!
        state.withLock { box in
            if let existing = box.conn {
                captured = existing
                return
            }
            let new = NSXPCConnection(serviceName: XPCService.bundleIdentifier)
            new.remoteObjectInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
            new.invalidationHandler = { [weak new] in new?.invalidate() }
            new.interruptionHandler = { [weak new] in new?.invalidate() }
            new.resume()
            box.conn = new
            captured = new
        }
        return captured.remoteObjectProxy as! any XPCFileServerProtocol
    }
}
