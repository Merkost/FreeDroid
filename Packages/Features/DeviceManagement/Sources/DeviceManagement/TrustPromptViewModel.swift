import Foundation
import Observation

@MainActor
@Observable
public final class TrustPromptViewModel {
    public private(set) var status: TrustStatus = .waiting
    public let serial: String
    private let observeUseCase: any ObserveTrustStatusUseCase
    private var observeTask: Task<Void, Never>?

    public init(serial: String, observe: any ObserveTrustStatusUseCase) {
        self.serial = serial
        self.observeUseCase = observe
    }

    public func start() {
        observeTask?.cancel()
        observeTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.observeUseCase(serial: self.serial) {
                await MainActor.run {
                    self.status = change
                }
            }
        }
    }

    public func stop() {
        observeTask?.cancel()
        observeTask = nil
    }

    public var isWaiting: Bool { status == .waiting }
    public var isAuthorized: Bool { status == .authorized }
}
