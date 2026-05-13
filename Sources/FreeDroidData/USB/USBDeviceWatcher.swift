import Foundation

public actor USBDeviceWatcher {
    private let center = USBNotificationCenter()
    private var consumers: [UUID: AsyncStream<USBNotificationEvent>.Continuation] = [:]
    private var task: Task<Void, Never>?

    public init() {}

    public func start() {
        guard task == nil else { return }
        center.start()
        task = Task { [weak self] in
            guard let self else { return }
            for await event in self.center.events() {
                await self.broadcast(event)
            }
        }
    }

    public func events() -> AsyncStream<USBNotificationEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<USBNotificationEvent>.Continuation) {
        consumers[id] = continuation
    }

    private func unregister(id: UUID) {
        consumers.removeValue(forKey: id)
    }

    private func broadcast(_ event: USBNotificationEvent) {
        for continuation in consumers.values {
            continuation.yield(event)
        }
    }

    public func stop() {
        center.stop()
        task?.cancel()
        task = nil
        for continuation in consumers.values {
            continuation.finish()
        }
        consumers.removeAll()
    }
}
