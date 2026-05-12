import Foundation
import FreeDroidProviderShared

actor ProviderTransport {
    let deviceID: DeviceID
    private var connection: NSXPCConnection?

    init(deviceID: DeviceID) {
        self.deviceID = deviceID
    }

    func invalidate() async {
        connection?.invalidate()
        connection = nil
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
        _ = try await send(
            .fetchToFile(deviceID: deviceID, path: path, destination: destination.path),
            expecting: Data.self
        )
    }

    func upload(from source: URL, to path: RemotePath) async throws {
        _ = try await send(
            .uploadFromFile(deviceID: deviceID, source: source.path, path: path),
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
        if connection == nil {
            let conn = NSXPCConnection(serviceName: XPCService.bundleIdentifier)
            conn.remoteObjectInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
            conn.invalidationHandler = { [weak conn] in conn?.invalidate() }
            conn.interruptionHandler = { [weak conn] in conn?.invalidate() }
            conn.resume()
            connection = conn
        }
        return connection!.remoteObjectProxy as! any XPCFileServerProtocol
    }
}
