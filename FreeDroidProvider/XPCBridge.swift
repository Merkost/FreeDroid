import Foundation
import FreeDroidProviderShared

@objc protocol XPCFileServerProtocol: Sendable {
    func send(_ payload: Data) async -> Data
}

actor XPCBridge {
    private var connection: NSXPCConnection?

    func send<T: Decodable>(_ request: IPCRequest, expecting: T.Type) async throws -> T {
        let payload = try IPCCoder.encoder.encode(request)
        let proxy = try await makeProxy()
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

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func makeProxy() async throws -> any XPCFileServerProtocol {
        if connection == nil {
            let endpoint = try await waitForEndpoint()
            let conn = NSXPCConnection(listenerEndpoint: endpoint)
            conn.remoteObjectInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
            conn.invalidationHandler = { [weak conn] in conn?.invalidate() }
            conn.interruptionHandler = { [weak conn] in conn?.invalidate() }
            conn.resume()
            connection = conn
        }
        return connection!.remoteObjectProxy as! any XPCFileServerProtocol
    }

    private func waitForEndpoint() async throws -> NSXPCListenerEndpoint {
        let maxAttempts = 20
        for attempt in 0..<maxAttempts {
            if let endpoint = try? readEndpoint() {
                return endpoint
            }
            if attempt < maxAttempts - 1 {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw TransportError.notConnected
    }

    private func readEndpoint() throws -> NSXPCListenerEndpoint {
        guard let url = IPCEndpoint.endpointFileURL() else {
            throw TransportError.notConnected
        }
        let data = try Data(contentsOf: url)
        guard let endpoint = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSXPCListenerEndpoint.self,
            from: data
        ) else {
            throw TransportError.notConnected
        }
        return endpoint
    }
}
