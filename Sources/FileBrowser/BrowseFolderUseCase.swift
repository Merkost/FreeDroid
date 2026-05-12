import FreeDroidDomain

public struct BrowseFolderUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(_ path: RemotePath) async throws -> [RemoteEntry] {
        try await fileRepository.list(path)
    }
}
