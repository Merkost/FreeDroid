import Foundation
import FreeDroidDomain
import UniformTypeIdentifiers

public struct DownloadToTempUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(entry: RemoteEntry) async throws -> URL {
        let ext = (entry.name as NSString).pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        let totalSize = entry.sizeBytes ?? 0
        let chunkSize = 1 * 1024 * 1024
        var offset: Int64 = 0
        var accumulated = Data()
        if totalSize == 0 {
            let chunk = try await fileRepository.read(entry.path, offset: 0, length: chunkSize)
            accumulated = chunk
        } else {
            while offset < totalSize {
                let remaining = Int(totalSize - offset)
                let toRead = min(remaining, chunkSize)
                let chunk = try await fileRepository.read(entry.path, offset: offset, length: toRead)
                accumulated.append(chunk)
                offset += Int64(chunk.count)
                if chunk.isEmpty { break }
            }
        }
        try accumulated.write(to: destination)
        return destination
    }
}

public enum QuickLookEligibility {
    public static func isPreviewable(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
            || type.conforms(to: .audiovisualContent)
            || type.conforms(to: .audio)
            || type.conforms(to: .pdf)
    }

    public static func isInlinePreviewable(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }
}
