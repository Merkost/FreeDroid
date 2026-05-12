public struct MediaPage: Hashable, Sendable, Codable {
    public let items: [MediaItem]
    public let hasMore: Bool
    public let nextPage: Int?

    public init(items: [MediaItem], hasMore: Bool, nextPage: Int?) {
        self.items = items
        self.hasMore = hasMore
        self.nextPage = nextPage
    }
}
