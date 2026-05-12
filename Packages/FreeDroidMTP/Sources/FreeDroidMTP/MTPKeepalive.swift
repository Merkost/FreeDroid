import Foundation

actor MTPKeepalive {
    private var task: Task<Void, Never>?

    func start(interval: Duration, action: @escaping @Sendable () async -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
