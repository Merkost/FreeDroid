import FreeDroidDomain

public struct DeviceRepositoryImpl: DeviceRepository {
    let registry: DeviceRegistry

    public init(registry: DeviceRegistry) {
        self.registry = registry
    }

    public func observe() -> AsyncStream<[Device]> {
        AsyncStream { continuation in
            Task {
                for await snapshot in await registry.observe() {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
        }
    }

    public func device(_ identifier: DeviceID) async -> Device? {
        await registry.device(identifier)
    }
}
