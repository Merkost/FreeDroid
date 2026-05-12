import Foundation
import FreeDroidDomain

public struct MediaSection: Identifiable, Sendable, Hashable {
    public let id: Date
    public let label: String
    public let items: [MediaItem]
}
