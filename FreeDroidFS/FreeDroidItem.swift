import Foundation
import FSKit
import FreeDroidDomain

final class FreeDroidItem: FSItem, @unchecked Sendable {
    let entry: RemoteEntry
    let deviceID: DeviceID

    init(deviceID: DeviceID, entry: RemoteEntry) {
        self.deviceID = deviceID
        self.entry = entry
        super.init()
    }
}
