import Foundation
import FreeDroidDomain

public struct ThumbnailCacheKey: Hashable, Sendable {
    public let deviceID: DeviceID
    public let path: RemotePath
    public let mtime: Date?
    public let size: ThumbnailSize

    public var diskKey: String {
        let mtimeRaw = mtime?.timeIntervalSince1970 ?? 0
        return "\(deviceID.raw)|\(path.raw)|\(mtimeRaw)|\(size.rawValue)"
    }
}

public actor ThumbnailCache {
    private let store: DiskLRUStore

    public init(rootURL: URL, capacityBytes: Int64 = 2 * 1024 * 1024 * 1024) {
        self.store = DiskLRUStore(rootURL: rootURL, capacityBytes: capacityBytes)
    }

    public func get(_ key: ThumbnailCacheKey) async -> Data? {
        await store.get(key.diskKey)
    }

    public func put(_ key: ThumbnailCacheKey, data: Data) async throws {
        try await store.put(key.diskKey, data: data)
    }

    public func clear() async {
        await store.clear()
    }
}
