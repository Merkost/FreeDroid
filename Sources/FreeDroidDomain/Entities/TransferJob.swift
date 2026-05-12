import Foundation

public enum Direction: String, Hashable, Sendable, Codable {
    case toMac
    case toDevice
}

public struct TransferJob: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let deviceID: DeviceID
    public let direction: Direction
    public let items: [RemotePath]
    public let destination: URL

    public init(
        id: UUID = UUID(),
        deviceID: DeviceID,
        direction: Direction,
        items: [RemotePath],
        destination: URL
    ) {
        self.id = id
        self.deviceID = deviceID
        self.direction = direction
        self.items = items
        self.destination = destination
    }
}
