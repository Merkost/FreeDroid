import Foundation

public struct TransferProgress: Hashable, Sendable, Codable {
    public let jobID: UUID
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let currentItem: RemotePath?
    public let bytesPerSecond: Double

    public init(
        jobID: UUID,
        completedBytes: Int64,
        totalBytes: Int64,
        currentItem: RemotePath?,
        bytesPerSecond: Double
    ) {
        self.jobID = jobID
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentItem = currentItem
        self.bytesPerSecond = bytesPerSecond
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(completedBytes) / Double(totalBytes)
    }
}
