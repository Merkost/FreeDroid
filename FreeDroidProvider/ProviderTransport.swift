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

    func fetch(_ path: RemotePath, into destination: URL) async throws {
        let data = try await send(
            .fetchData(deviceID: deviceID, path: path),
            expecting: Data.self
        )
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try data.write(to: destination)
    }

    func upload(from source: URL, to path: RemotePath) async throws {
        let data = try Data(contentsOf: source)
        _ = try await send(
            .uploadData(deviceID: deviceID, path: path, data: data),
            expecting: Data.self
        )
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
