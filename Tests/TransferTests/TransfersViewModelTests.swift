import Foundation
import Testing
import FreeDroidDomain
@testable import Transfer

final class StubTransferRepository: TransferRepository, @unchecked Sendable {
    let stream: AsyncStream<[TransferState]>
    let continuation: AsyncStream<[TransferState]>.Continuation

    init() {
        var cont: AsyncStream<[TransferState]>.Continuation!
        self.stream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func enqueue(_ job: TransferJob) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { cont in cont.finish() }
    }

    func cancel(_ jobID: UUID) async {}
    func observe() -> AsyncStream<[TransferState]> { stream }

    func emit(_ states: [TransferState]) {
        continuation.yield(states)
    }
}

@MainActor
@Suite("TransfersViewModel")
struct TransfersViewModelTests {
    private func drain() async throws {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func observesStateStream() async throws {
        let repo = StubTransferRepository()
        let viewModel = TransfersViewModel(repository: repo, cancel: CancelTransferUseCase(repository: repo))
        let task = Task { await viewModel.observe() }
        let jobID = UUID()
        let progress = TransferProgress(
            jobID: jobID,
            completedBytes: 50,
            totalBytes: 100,
            currentItem: nil,
            bytesPerSecond: 0
        )
        await Task.yield()
        repo.emit([.running(progress)])
        try await drain()
        #expect(viewModel.states.count == 1)
        task.cancel()
    }
}
