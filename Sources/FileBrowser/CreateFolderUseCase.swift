import FreeDroidDomain

public struct CreateFolderUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(at parent: RemotePath, name: String) async throws -> RemotePath {
        let target = parent.appending(name)
        try await fileRepository.mkdir(target)
        return target
    }
}
