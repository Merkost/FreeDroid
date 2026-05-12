import Foundation
import FreeDroidDomain

public struct PerDeviceProgressDeriver: Sendable {
    public init() {}

    public func derive(
        states: [TransferState],
        deviceForJob: (UUID) -> DeviceID?
    ) -> [DeviceID: Double] {
        var totals: [DeviceID: (Int64, Int64)] = [:]
        for state in states {
            switch state {
            case .running(let transferProgress), .paused(let transferProgress):
                guard let device = deviceForJob(transferProgress.jobID) else { continue }
                let pair = totals[device] ?? (0, 0)
                totals[device] = (pair.0 + transferProgress.completedBytes, pair.1 + max(transferProgress.totalBytes, 1))
            case .idle, .completed, .failed:
                continue
            }
        }
        return totals.mapValues { Double($0.0) / Double($0.1) }
    }
}
