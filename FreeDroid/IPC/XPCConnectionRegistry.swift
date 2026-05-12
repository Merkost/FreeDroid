import Foundation
import FreeDroidDomain
import FreeDroidData

@MainActor
final class XPCConnectionRegistry {
    private(set) var server: XPCFileServer?

    func start(registry: DeviceRegistry) {
        let handler = XPCFileServerHandler(registry: registry)
        server = XPCFileServer(handler: handler)
        server?.start()
    }
}
