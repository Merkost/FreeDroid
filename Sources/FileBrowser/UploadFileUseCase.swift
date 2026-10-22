import Foundation
import FreeDroidDomain

public struct UploadFileUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(source: URL, destinationFolder: RemotePath) async throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }

        let destination = destinationFolder.appending(source.lastPathComponent)
        if let localSize = try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber,
           let remote = try? await fileRepository.stat(destination),
           remote.kind == .file,
           remote.sizeBytes == localSize.int64Value {
            return
        }
        _ = try await fileRepository.upload(from: source, to: destination, progress: nil)
    }
}
