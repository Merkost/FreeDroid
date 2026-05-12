import Foundation

public struct MTPObject: Hashable, Sendable {
    public let storageID: UInt32
    public let objectHandle: UInt32
    public let parentHandle: UInt32
    public let name: String
    public let isFolder: Bool
    public let size: Int64
    public let modifiedAt: Date?
}
