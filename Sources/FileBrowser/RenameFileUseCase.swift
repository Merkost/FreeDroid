import FreeDroidDomain

public struct RenameFileUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(from: RemotePath, to dest: RemotePath) async throws {
        try await fileRepository.rename(from, to: dest)
    }
}
