import FreeDroidDomain

public struct DeleteFilesUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(paths: [RemotePath]) async throws {
        for path in paths {
            try await fileRepository.remove(path)
        }
    }
}
