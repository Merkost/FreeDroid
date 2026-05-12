public enum ThumbnailSize: String, Hashable, Sendable, Codable, CaseIterable {
    case small
    case medium
    case large

    public var pixels: Int {
        switch self {
        case .small: 128
        case .medium: 256
        case .large: 512
        }
    }
}
