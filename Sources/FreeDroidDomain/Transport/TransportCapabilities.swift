public struct TransportCapabilities: Hashable, Sendable, Codable {
    public let supportsRangeRead: Bool
    public let supportsRangeWrite: Bool
    public let supportsSymlinks: Bool
    public let recommendedChunkBytes: Int

    public init(
        supportsRangeRead: Bool,
        supportsRangeWrite: Bool,
        supportsSymlinks: Bool,
        recommendedChunkBytes: Int
    ) {
        self.supportsRangeRead = supportsRangeRead
        self.supportsRangeWrite = supportsRangeWrite
        self.supportsSymlinks = supportsSymlinks
        self.recommendedChunkBytes = recommendedChunkBytes
    }
}
