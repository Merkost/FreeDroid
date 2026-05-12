import Foundation

public enum MountStrategyKind: String, Hashable, Sendable, Codable {
    case fskit
    case fileProvider
    case mock
}

public struct MountedVolume: Hashable, Sendable, Codable {
    public let deviceID: DeviceID
    public let mountURL: URL
    public let strategyKind: MountStrategyKind

    public init(deviceID: DeviceID, mountURL: URL, strategyKind: MountStrategyKind) {
        self.deviceID = deviceID
        self.mountURL = mountURL
        self.strategyKind = strategyKind
    }
}
