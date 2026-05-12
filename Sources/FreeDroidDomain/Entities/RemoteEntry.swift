import Foundation

public enum EntryKind: String, Hashable, Sendable, Codable {
    case file
    case directory
    case symlink
}

public struct RemoteEntry: Hashable, Sendable, Codable, Identifiable {
    public var id: RemotePath { path }
    public let path: RemotePath
    public let name: String
    public let kind: EntryKind
    public let sizeBytes: Int64?
    public let modifiedAt: Date?
    public let isHidden: Bool

    public init(
        path: RemotePath,
        name: String,
        kind: EntryKind,
        sizeBytes: Int64?,
        modifiedAt: Date?,
        isHidden: Bool
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.isHidden = isHidden
    }
}
