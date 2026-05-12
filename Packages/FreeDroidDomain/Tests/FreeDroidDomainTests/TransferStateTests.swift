import Foundation
import Testing
@testable import FreeDroidDomain

@Suite("TransferState")
struct TransferStateTests {
    private func progress(fraction: Double) -> TransferProgress {
        TransferProgress(
            jobID: UUID(),
            completedBytes: Int64(fraction * 100),
            totalBytes: 100,
            currentItem: nil,
            bytesPerSecond: 1024
        )
    }

    @Test func progressFractionIsCorrect() {
        let prog = progress(fraction: 0.5)
        #expect(prog.fraction == 0.5)
    }

    @Test func progressFractionIsZeroWhenTotalIsZero() {
        let prog = TransferProgress(
            jobID: UUID(),
            completedBytes: 0,
            totalBytes: 0,
            currentItem: nil,
            bytesPerSecond: 0
        )
        #expect(prog.fraction == 0)
    }

    @Test func transferStateRunningCarriesProgress() {
        let state = TransferState.running(progress(fraction: 0.25))
        if case let .running(prog) = state {
            #expect(prog.fraction == 0.25)
        } else {
            Issue.record("expected .running case")
        }
    }
}
