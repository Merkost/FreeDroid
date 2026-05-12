import Foundation
import FreeDroidIPC

@objc protocol XPCFileServerProtocol {
    func send(_ payload: Data) async -> Data
}

final class XPCFileServer: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let handler: XPCFileServerHandler

    init(handler: XPCFileServerHandler) {
        self.handler = handler
        self.listener = NSXPCListener(machServiceName: IPCEndpoint.machServiceName)
        super.init()
        self.listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
        newConnection.exportedObject = XPCFileServerExportedObject(handler: handler)
        newConnection.resume()
        return true
    }
}

final class XPCFileServerExportedObject: NSObject, XPCFileServerProtocol {
    private let handler: XPCFileServerHandler

    init(handler: XPCFileServerHandler) {
        self.handler = handler
    }

    func send(_ payload: Data) async -> Data {
        await handler.handle(payload: payload)
    }
}
