import Foundation
import AppKit
import FreeDroidDomain

public struct MediaRepositoryImpl: MediaRepository {
    private let registry: DeviceRegistry
    private let fileRepo: FileRepository
    private let thumbnails: ThumbnailCache
    private let deviceID: DeviceID

    public init(
        registry: DeviceRegistry,
        fileRepo: FileRepository,
        thumbnails: ThumbnailCache,
        deviceID: DeviceID
    ) {
        self.registry = registry
        self.fileRepo = fileRepo
        self.thumbnails = thumbnails
        self.deviceID = deviceID
    }

    public func listMedia(in folder: RemotePath, page: Int) async throws -> MediaPage {
        let entries = try await fileRepo.list(folder)
        let mediaEntries = entries
            .filter { $0.kind == .file }
            .filter { isMedia($0.name) }
        let pageSize = 100
        let start = page * pageSize
        let end = min(start + pageSize, mediaEntries.count)
        guard start < mediaEntries.count else {
            return MediaPage(items: [], hasMore: false, nextPage: nil)
        }
        let slice = mediaEntries[start..<end].map { entry in
            MediaItem(
                id: entry.path.raw,
                path: entry.path,
                kind: isImage(entry.name) ? .image : .video,
                captureDate: entry.modifiedAt,
                sizeBytes: entry.sizeBytes ?? 0
            )
        }
        let more = end < mediaEntries.count
        return MediaPage(items: Array(slice), hasMore: more, nextPage: more ? page + 1 : nil)
    }

    public func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> Data {
        let key = ThumbnailCacheKey(
            deviceID: deviceID,
            path: item.path,
            mtime: item.captureDate,
            size: size
        )
        if let cached = await thumbnails.get(key) { return cached }
        let full = try await fileRepo.read(item.path, offset: 0, length: 8 * 1024 * 1024)
        let thumb = try downscale(full, to: size.pixels)
        try await thumbnails.put(key, data: thumb)
        return thumb
    }

    private func isMedia(_ name: String) -> Bool {
        let lower = name.lowercased()
        let exts = ["jpg", "jpeg", "png", "heic", "webp", "gif", "mp4", "mov", "m4v", "webm"]
        return exts.contains { lower.hasSuffix(".\($0)") }
    }

    private func isImage(_ name: String) -> Bool {
        let lower = name.lowercased()
        let exts = ["jpg", "jpeg", "png", "heic", "webp", "gif"]
        return exts.contains { lower.hasSuffix(".\($0)") }
    }

    private func downscale(_ data: Data, to maxPixels: Int) throws -> Data {
        guard let source = NSImage(data: data) else {
            throw TransportError.ioFailure(message: "cannot decode image")
        }
        let aspect = source.size.height == 0 ? 1.0 : source.size.width / source.size.height
        let targetSize: NSSize = source.size.width > source.size.height
            ? NSSize(width: maxPixels, height: Int(Double(maxPixels) / max(aspect, 0.0001)))
            : NSSize(width: Int(Double(maxPixels) * aspect), height: maxPixels)
        let resized = NSImage(size: targetSize, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
            throw TransportError.ioFailure(message: "cannot encode thumbnail")
        }
        return jpeg
    }
}
