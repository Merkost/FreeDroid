import Foundation
import FreeDroidDomain

public struct CancelTransferUseCase: Sendable {
    public let repository: any TransferRepository

    public init(repository: any TransferRepository) {
        self.repository = repository
    }

    public func callAsFunction(_ jobID: UUID) async {
        await repository.cancel(jobID)
    }
}
