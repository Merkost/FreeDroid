import Foundation
import FreeDroidIPC
import os.log

private let bridgeLogger = Logger(subsystem: "com.merkost.freedroid", category: "bridge")

final class BridgeService: NSObject, NSXPCListenerDelegate {
    private let handler: BridgeHandler

    override init() {
        do {
            self.handler = try BridgeHandler()
        } catch {
            bridgeLogger.error("BridgeHandler init failed: \(String(describing: error), privacy: .public)")
            fatalError("BridgeHandler init failed: \(error)")
        }
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
        connection.exportedObject = BridgeExportedObject(handler: handler)
        connection.resume()
        bridgeLogger.info("Bridge accepted new connection")
        return true
    }
}

final class BridgeExportedObject: NSObject, XPCFileServerProtocol {
    private let handler: BridgeHandler

    init(handler: BridgeHandler) {
        self.handler = handler
    }

    func send(_ payload: Data) async -> Data {
        await handler.handle(payload: payload)
    }
}
