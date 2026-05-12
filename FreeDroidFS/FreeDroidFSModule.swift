import Foundation
import FSKit
import FreeDroidDomain
import os.log

private let logger = Logger(subsystem: "com.merkost.freedroid.FreeDroidFS", category: "module")

@objc(FreeDroidFSModule)
final class FreeDroidFSModule: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    let client = XPCClient()

    func probeResource(
        resource: FSResource,
        replyHandler: @escaping @Sendable (FSProbeResult?, (any Error)?) -> Void
    ) {
        let serial = extractSerial(from: resource)
        let containerID = VolumeIdentifierMint.containerID(for: serial)
        replyHandler(.recognized(name: "FreeDroid", containerID: containerID), nil)
    }

    func loadResource(
        resource: FSResource,
        options: FSTaskOptions,
        replyHandler: @escaping @Sendable (FSVolume?, (any Error)?) -> Void
    ) {
        let serial = extractSerial(from: resource)
        let displayName = extractDisplayName(from: resource)
        logger.info("Loading resource for device \(serial, privacy: .public) (\(displayName, privacy: .public))")
        let deviceID = DeviceID(raw: serial)
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
        let serial = extractSerial(from: resource)
        logger.info("Unloading resource for device \(serial, privacy: .public)")
        replyHandler(nil)
    }

    private func extractSerial(from resource: FSResource) -> String {
        if #available(macOS 26.0, *), let urlResource = resource as? FSGenericURLResource {
            return urlResource.url.host ?? UUID().uuidString
        }
        return UUID().uuidString
    }

    private func extractDisplayName(from resource: FSResource) -> String {
        if #available(macOS 26.0, *), let urlResource = resource as? FSGenericURLResource {
            let rawPath = urlResource.url.lastPathComponent
            return rawPath.removingPercentEncoding ?? rawPath
        }
        return "Android Device"
    }
}
