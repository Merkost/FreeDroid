import Foundation

public enum MediaKind: String, Hashable, Sendable, Codable {
    case image
    case video
}

public struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let path: RemotePath
    public let kind: MediaKind
    public let captureDate: Date?
    public let sizeBytes: Int64

    public init(
        id: String,
        path: RemotePath,
        kind: MediaKind,
        captureDate: Date?,
        sizeBytes: Int64
    ) {
        self.id = id
        self.path = path
        self.kind = kind
        self.captureDate = captureDate
        self.sizeBytes = sizeBytes
    }
}
