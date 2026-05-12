import Foundation
import FSKit
import FreeDroidDomain
import os.log

private let logger = Logger(subsystem: "com.merkost.freedroid.FreeDroidFS", category: "module")

final class FreeDroidFSModule: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    let client = XPCClient()

    func probeResource(
        resource: FSResource,
        replyHandler: @escaping @Sendable (FSProbeResult?, (any Error)?) -> Void
    ) {
        let containerID = FSContainerIdentifier(uuid: UUID())
        replyHandler(.recognized(name: "FreeDroid", containerID: containerID), nil)
    }

    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping @Sendable (FSVolume?, (any Error)?) -> Void
    ) {
        let deviceID = DeviceID(raw: UUID().uuidString)
        let displayName = "Android Device"
        let volume = FreeDroidVolume(
            deviceID: deviceID,
            displayName: displayName,
            client: client
        )
        replyHandler(volume, nil)
    }

    func unloadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        replyHandler(nil)
    }
}
