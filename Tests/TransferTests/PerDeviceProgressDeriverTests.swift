import Foundation
import Testing
import FreeDroidDomain
@testable import Transfer

@Suite("PerDeviceProgressDeriver")
struct PerDeviceProgressDeriverTests {
    private func progress(_ jobID: UUID, completed: Int64, total: Int64) -> TransferProgress {
        TransferProgress(jobID: jobID, completedBytes: completed, totalBytes: total, currentItem: nil, bytesPerSecond: 0)
    }

    @Test func mergesProgressFromMultipleJobsForSameDevice() {
        let deviceID = DeviceID(raw: "A")
        let jobsByDevice: [DeviceID: [UUID]] = [
            deviceID: [UUID(), UUID()]
        ]
        let jobs = jobsByDevice[deviceID] ?? []
        let states: [TransferState] = [
            .running(progress(jobs[0], completed: 50, total: 100)),
            .running(progress(jobs[1], completed: 200, total: 400))
        ]
        let deriver = PerDeviceProgressDeriver()
        let map = deriver.derive(states: states, deviceForJob: { _ in deviceID })
        #expect(map[deviceID] == 0.5)
    }

    @Test func completedJobsContributeFully() {
        let deviceID = DeviceID(raw: "A")
        let states: [TransferState] = [.completed]
        let deriver = PerDeviceProgressDeriver()
        let map = deriver.derive(states: states, deviceForJob: { _ in deviceID })
        #expect(map[deviceID] == nil)
    }
}
