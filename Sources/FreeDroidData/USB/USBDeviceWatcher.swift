import Foundation

public actor USBDeviceWatcher {
    private let center = USBNotificationCenter()
    private var consumers: [AsyncStream<USBNotificationEvent>.Continuation] = []
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
        let (stream, continuation) = AsyncStream<USBNotificationEvent>.makeStream()
        consumers.append(continuation)
        return stream
    }

    private func broadcast(_ event: USBNotificationEvent) {
        for continuation in consumers {
            continuation.yield(event)
        }
    }

    public func stop() {
        center.stop()
        task?.cancel()
        task = nil
        for continuation in consumers {
            continuation.finish()
        }
        consumers.removeAll()
    }
}
