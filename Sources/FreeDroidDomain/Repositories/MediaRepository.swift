import Foundation

public protocol MediaRepository: Sendable {
    func listMedia(in folder: RemotePath, page: Int) async throws -> MediaPage
    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> Data
}
