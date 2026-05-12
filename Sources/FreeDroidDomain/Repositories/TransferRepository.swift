import Foundation

public protocol TransferRepository: Sendable {
    func enqueue(_ job: TransferJob) -> AsyncThrowingStream<TransferProgress, Error>
    func cancel(_ jobID: UUID) async
    func observe() -> AsyncStream<[TransferState]>
}
