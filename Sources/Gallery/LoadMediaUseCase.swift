import FreeDroidDomain

public struct LoadMediaUseCase: Sendable {
    public let mediaRepository: any MediaRepository

    public init(mediaRepository: any MediaRepository) {
        self.mediaRepository = mediaRepository
    }

    public func callAsFunction(folder: RemotePath, page: Int = 0) async throws -> MediaPage {
        try await mediaRepository.listMedia(in: folder, page: page)
    }
}
