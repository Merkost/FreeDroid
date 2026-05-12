import Foundation
import FreeDroidDomain

public struct TransferRepositoryImpl: TransferRepository {
    private let queue: TransferQueue
    private let registry: DeviceRegistry

    public init(queue: TransferQueue, registry: DeviceRegistry) {
        self.queue = queue
        self.registry = registry
    }

    public func enqueue(_ job: TransferJob) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let transport = await registry.transport(for: job.deviceID) else {
                    continuation.finish(throwing: TransportError.notConnected)
                    return
                }
                let engine = TransferEngine(transport: transport)
                let stream = await queue.enqueue(job, engine: engine)
                do {
                    for try await progress in stream { continuation.yield(progress) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancel(_ jobID: UUID) async {
        await queue.cancel(jobID)
    }

    public func observe() -> AsyncStream<[TransferState]> {
        AsyncStream { continuation in
            Task {
                for await snapshot in await queue.observe() {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
        }
    }
}
