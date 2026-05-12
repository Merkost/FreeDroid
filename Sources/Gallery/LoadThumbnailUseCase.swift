import Foundation
import FreeDroidDomain

public struct LoadThumbnailUseCase: Sendable {
    public let mediaRepository: any MediaRepository

    public init(mediaRepository: any MediaRepository) {
        self.mediaRepository = mediaRepository
    }

    public func callAsFunction(for item: MediaItem, size: ThumbnailSize = .medium) async throws -> Data {
        try await mediaRepository.thumbnail(for: item, size: size)
    }
}
