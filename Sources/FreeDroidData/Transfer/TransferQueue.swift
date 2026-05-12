import Foundation
import FreeDroidDomain

public actor TransferQueue {
    private struct ActiveJob {
        let job: TransferJob
        var task: Task<Void, Never>
    }

    private var active: [UUID: ActiveJob] = [:]
    private var stateSubscribers: [AsyncStream<[TransferState]>.Continuation] = []
    private var jobStates: [UUID: TransferState] = [:]
    private let maxParallelPerDevice: Int

    public init(maxParallelPerDevice: Int = TransferQueue.defaultParallelism()) {
        self.maxParallelPerDevice = max(1, min(maxParallelPerDevice, 16))
    }

    public static func defaultParallelism() -> Int {
        let stored = UserDefaults.standard.integer(forKey: "FreeDroid.ParallelTransfersPerDevice")
        return stored == 0 ? 3 : max(1, min(stored, 16))
    }

    public func enqueue(_ job: TransferJob, engine: TransferEngine) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            let workTask = Task {
                let initialProgress = TransferProgress(
                    jobID: job.id,
                    completedBytes: 0,
                    totalBytes: 0,
                    currentItem: nil,
                    bytesPerSecond: 0
                )
                jobStates[job.id] = .running(initialProgress)
                publish()
                do {
                    let total = try await self.computeTotal(job: job, engine: engine)
                    let copied = try await self.runParallelPull(
                        job: job,
                        engine: engine,
                        total: total,
                        continuation: continuation
                    )
                    let finalProgress = TransferProgress(
                        jobID: job.id,
                        completedBytes: copied,
                        totalBytes: total,
                        currentItem: nil,
                        bytesPerSecond: 0
                    )
                    jobStates[job.id] = .running(finalProgress)
                    publish()
                    jobStates[job.id] = .completed
                    publish()
                    continuation.finish()
                } catch {
                    if let transportError = error as? TransportError {
                        jobStates[job.id] = .failed(transportError)
                    } else if error is CancellationError {
                        jobStates[job.id] = .failed(.cancelled)
                    } else {
                        jobStates[job.id] = .failed(.ioFailure(message: String(describing: error)))
                    }
                    publish()
                    continuation.finish(throwing: error)
                }
                active[job.id] = nil
            }
            active[job.id] = ActiveJob(job: job, task: workTask)
            continuation.onTermination = { _ in Task { await self.cancel(job.id) } }
        }
    }

    public func cancel(_ jobID: UUID) async {
        active[jobID]?.task.cancel()
    }

    public func observe() -> AsyncStream<[TransferState]> {
        AsyncStream { continuation in
            Task { await self.subscribe(continuation) }
            continuation.onTermination = { _ in }
        }
    }

    private func subscribe(_ continuation: AsyncStream<[TransferState]>.Continuation) {
        stateSubscribers.append(continuation)
        continuation.yield(Array(jobStates.values))
    }

    private func publish() {
        let snapshot = Array(jobStates.values)
        for subscriber in stateSubscribers { subscriber.yield(snapshot) }
    }

    private func computeTotal(job: TransferJob, engine: TransferEngine) async throws -> Int64 {
        var total: Int64 = 0
        for item in job.items {
            let entry = try await engine.transport.stat(item)
            total += entry.sizeBytes ?? 0
        }
        return total
    }

    private func runParallelPull(
        job: TransferJob,
        engine: TransferEngine,
        total: Int64,
        continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws -> Int64 {
        let limit = maxParallelPerDevice
        let jobID = job.id
        let destination = job.destination
        var copied: Int64 = 0
        try await withThrowingTaskGroup(of: (RemotePath, Int64).self) { group in
            var inFlight = 0
            var index = 0
            let items = job.items
            while index < items.count && inFlight < limit {
                let item = items[index]
                index += 1
                inFlight += 1
                group.addTask {
                    let local = destination.appendingPathComponent(item.name)
                    let bytes = try await engine.pull(item, to: local)
                    return (item, bytes)
                }
            }
            while let result = try await group.next() {
                inFlight -= 1
                let (item, bytes) = result
                copied += bytes
                let progress = TransferProgress(
                    jobID: jobID,
                    completedBytes: copied,
                    totalBytes: total,
                    currentItem: item,
                    bytesPerSecond: 0
                )
                jobStates[jobID] = .running(progress)
                publish()
                continuation.yield(progress)
                if index < items.count {
                    try Task.checkCancellation()
                    let next = items[index]
                    index += 1
                    inFlight += 1
                    group.addTask {
                        let local = destination.appendingPathComponent(next.name)
                        let bytes = try await engine.pull(next, to: local)
                        return (next, bytes)
                    }
                }
            }
        }
        return copied
    }
}
