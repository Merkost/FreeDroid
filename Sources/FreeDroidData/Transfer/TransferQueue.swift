import Foundation
import FreeDroidDomain

public actor TransferQueue {
    private struct ActiveJob {
        let job: TransferJob
        var task: Task<Void, Never>
    }

    private var active: [UUID: ActiveJob] = [:]
    private var stateSubscribers: [UUID: AsyncStream<[TransferState]>.Continuation] = [:]
    private var jobStates: [UUID: TransferState] = [:]
    private let maxParallelPerDevice: Int

    public init(maxParallelPerDevice: Int = TransferQueue.defaultParallelism()) {
        self.maxParallelPerDevice = max(1, min(maxParallelPerDevice, 16))
    }

    public static func defaultParallelism() -> Int {
        let suite = UserDefaults(suiteName: "group.com.merkost.freedroid") ?? .standard
        let stored = suite.integer(forKey: "FreeDroid.ParallelTransfersPerDevice")
        return stored == 0 ? 3 : max(1, min(stored, 16))
    }

    public func enqueue(_ job: TransferJob, engine: TransferEngine) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            let workTask = Task {
                await self.start(job: job, engine: engine, continuation: continuation)
            }
            active[job.id] = ActiveJob(job: job, task: workTask)
            continuation.onTermination = { _ in Task { await self.cancel(job.id) } }
        }
    }

    public func cancel(_ jobID: UUID) async {
        active[jobID]?.task.cancel()
    }

    public func observe() -> AsyncStream<[TransferState]> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.subscribe(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unsubscribe(id: id) }
            }
        }
    }

    private func start(
        job: TransferJob,
        engine: TransferEngine,
        continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async {
        publishRunning(job.id, completed: 0, total: 0, current: nil)
        do {
            let total = try await computeTotal(job: job, engine: engine)
            let copied = try await runParallel(job: job, engine: engine, total: total, continuation: continuation)
            publishRunning(job.id, completed: copied, total: total, current: nil)
            jobStates[job.id] = .completed
            publish()
            continuation.finish()
        } catch {
            jobStates[job.id] = mapFailure(error)
            publish()
            continuation.finish(throwing: error)
        }
        active[job.id] = nil
    }

    private func mapFailure(_ error: Error) -> TransferState {
        if let transportError = error as? TransportError {
            return .failed(transportError)
        }
        if error is CancellationError {
            return .failed(.cancelled)
        }
        return .failed(.ioFailure(message: String(describing: error)))
    }

    private func subscribe(id: UUID, continuation: AsyncStream<[TransferState]>.Continuation) {
        stateSubscribers[id] = continuation
        continuation.yield(Array(jobStates.values))
    }

    private func unsubscribe(id: UUID) {
        stateSubscribers.removeValue(forKey: id)
    }

    private func publish() {
        let snapshot = Array(jobStates.values)
        for subscriber in stateSubscribers.values { subscriber.yield(snapshot) }
    }

    private func publishRunning(_ jobID: UUID, completed: Int64, total: Int64, current: RemotePath?) {
        let progress = TransferProgress(
            jobID: jobID,
            completedBytes: completed,
            totalBytes: total,
            currentItem: current,
            bytesPerSecond: 0
        )
        jobStates[jobID] = .running(progress)
        publish()
    }

    private func computeTotal(job: TransferJob, engine: TransferEngine) async throws -> Int64 {
        switch job.direction {
        case .toMac:
            var total: Int64 = 0
            for item in job.items {
                let entry = try await engine.transport.stat(item)
                total += entry.sizeBytes ?? 0
            }
            return total
        case .toDevice:
            var total: Int64 = 0
            for item in job.items {
                let local = job.destination.appendingPathComponent(item.name)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: local.path),
                   let size = (attrs[.size] as? NSNumber)?.int64Value {
                    total += size
                }
            }
            return total
        }
    }

    private func runParallel(
        job: TransferJob,
        engine: TransferEngine,
        total: Int64,
        continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws -> Int64 {
        let worker = makeWorker(for: job, engine: engine)
        let items = job.items
        let limit = maxParallelPerDevice
        var copied: Int64 = 0

        try await withThrowingTaskGroup(of: (RemotePath, Int64).self) { group in
            var inFlight = 0
            var index = 0
            func enqueueNext() {
                guard index < items.count else { return }
                let item = items[index]
                index += 1
                inFlight += 1
                group.addTask {
                    let bytes = try await worker(item)
                    return (item, bytes)
                }
            }
            while inFlight < limit && index < items.count { enqueueNext() }
            while let (item, bytes) = try await group.next() {
                inFlight -= 1
                copied += bytes
                publishRunning(job.id, completed: copied, total: total, current: item)
                continuation.yield(TransferProgress(
                    jobID: job.id,
                    completedBytes: copied,
                    totalBytes: total,
                    currentItem: item,
                    bytesPerSecond: 0
                ))
                try Task.checkCancellation()
                enqueueNext()
            }
        }
        return copied
    }

    private func makeWorker(for job: TransferJob, engine: TransferEngine) -> @Sendable (RemotePath) async throws -> Int64 {
        let destination = job.destination
        switch job.direction {
        case .toMac:
            return { item in
                try await engine.pull(item, to: destination.appendingPathComponent(item.name))
            }
        case .toDevice:
            return { item in
                try await engine.push(localURL: destination.appendingPathComponent(item.name), to: item)
            }
        }
    }
}
