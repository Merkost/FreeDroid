import Foundation
import FreeDroidIPC
import os.log

@objc protocol XPCFileServerProtocol {
    func send(_ payload: Data) async -> Data
}

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
        publishEndpoint()
    }

    private func publishEndpoint() {
        guard let url = IPCEndpoint.endpointFileURL() else {
            Self.logger.error("App group container missing; XPC endpoint cannot be published")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try NSKeyedArchiver.archivedData(withRootObject: listener.endpoint, requiringSecureCoding: true)
            try data.write(to: url, options: [.atomic])
            Self.logger.info("Published XPC endpoint at \(url.path, privacy: .public)")
        } catch {
            Self.logger.error("Failed to publish XPC endpoint: \(String(describing: error), privacy: .public)")
        }
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
