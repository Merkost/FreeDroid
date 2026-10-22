import Foundation

public struct TransferHistoryEntry: Identifiable, Hashable, Sendable, Codable {
    public enum Result: String, Hashable, Sendable, Codable {
        case completed
        case failed
        case cancelled
    }

    public let id: UUID
    public let deviceID: DeviceID
    public let direction: Direction
    public let itemCount: Int
    public let bytes: Int64
    public let startedAt: Date
    public let finishedAt: Date
    public let result: Result
    public let message: String?

    public init(id: UUID = UUID(), deviceID: DeviceID, direction: Direction, itemCount: Int, bytes: Int64, startedAt: Date, finishedAt: Date, result: Result, message: String? = nil) {
        self.id = id
        self.deviceID = deviceID
        self.direction = direction
        self.itemCount = itemCount
        self.bytes = bytes
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.result = result
        self.message = message
    }
}
