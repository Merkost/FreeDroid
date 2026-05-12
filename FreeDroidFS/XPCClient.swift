import Foundation
import FreeDroidIPC
import FreeDroidDomain

@objc protocol XPCFileServerProtocol {
    func send(_ payload: Data) async -> Data
}

final class XPCProxyBox: @unchecked Sendable {
    let proxy: any XPCFileServerProtocol

    init(_ proxy: any XPCFileServerProtocol) {
        self.proxy = proxy
    }
}

actor XPCClient {
    private var connection: NSXPCConnection?

    func proxyBox() -> XPCProxyBox {
        if connection == nil {
            let conn = NSXPCConnection(machServiceName: IPCEndpoint.machServiceName, options: [])
            conn.remoteObjectInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
            conn.invalidationHandler = { [weak conn] in
                conn?.invalidate()
            }
            conn.resume()
            connection = conn
        }
        let rawProxy = connection!.remoteObjectProxy as! (any XPCFileServerProtocol)
        return XPCProxyBox(rawProxy)
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    func send<T: Decodable>(_ request: IPCRequest, expecting: T.Type) async throws -> T {
        let box = proxyBox()
        let payload = try IPCCoder.encoder.encode(request)
        let responseData = await box.proxy.send(payload)
        let response = try IPCCoder.decoder.decode(IPCResponse.self, from: responseData)
        switch response {
        case .entries(let entries) where T.self == [RemoteEntry].self:
            return entries as! T
        case .entry(let entry) where T.self == RemoteEntry.self:
            return entry as! T
        case .data(let data) where T.self == Data.self:
            return data as! T
        case .failure(let ipcError):
            switch ipcError {
            case .transport(let transportError): throw transportError
            case .noTransport: throw TransportError.notConnected
            case .decodingFailed(let message): throw TransportError.ioFailure(message: message)
            }
        default:
            throw TransportError.ioFailure(message: "Unexpected XPC response")
        }
    }
}
