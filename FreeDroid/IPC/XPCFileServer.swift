import Foundation
import FreeDroidIPC
import os.log

final class XPCFileServer: NSObject, NSXPCListenerDelegate {
    private static let logger = Logger(subsystem: "com.merkost.freedroid", category: "xpc-server")
    private let listener: NSXPCListener
    private let handler: XPCFileServerHandler

    init(handler: XPCFileServerHandler) {
        self.handler = handler
        self.listener = NSXPCListener.anonymous()
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
