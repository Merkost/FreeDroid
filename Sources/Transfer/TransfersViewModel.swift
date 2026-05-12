import Foundation
import Observation
import FreeDroidDomain

@MainActor
@Observable
public final class TransfersViewModel {
    public private(set) var states: [TransferState] = []
    public private(set) var jobToDevice: [UUID: DeviceID] = [:]
    public private(set) var deviceFractions: [DeviceID: Double] = [:]

    private let repository: any TransferRepository
    private let cancelUseCase: CancelTransferUseCase
    private let deriver = PerDeviceProgressDeriver()

    public init(repository: any TransferRepository, cancel: CancelTransferUseCase) {
        self.repository = repository
        self.cancelUseCase = cancel
    }

    public func observe() async {
        for await snapshot in repository.observe() {
            states = snapshot
            recomputeDeviceFractions()
        }
    }

    public func register(jobID: UUID, on deviceID: DeviceID) {
        jobToDevice[jobID] = deviceID
        recomputeDeviceFractions()
    }

    public func cancel(_ jobID: UUID) async {
        await cancelUseCase(jobID)
    }

    private func recomputeDeviceFractions() {
        deviceFractions = deriver.derive(states: states) { jobID in
            jobToDevice[jobID]
        }
    }
}
