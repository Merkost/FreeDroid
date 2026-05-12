import Foundation
import Testing
import FreeDroidDomain
@testable import FreeDroidData

@Suite("ThumbnailCache")
struct ThumbnailCacheTests {
    private func makeCache() -> (ThumbnailCache, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("freedroid-thumb-\(UUID().uuidString)", isDirectory: true)
        return (ThumbnailCache(rootURL: root, capacityBytes: 4096), root)
    }

    @Test func storeAndRetrieve() async throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = ThumbnailCacheKey(
            deviceID: DeviceID(raw: "DEV"),
            path: RemotePath(raw: "/x.jpg"),
            mtime: Date(timeIntervalSince1970: 1000),
            size: .medium
        )
        try await cache.put(key, data: Data([1, 2, 3]))
        let out = await cache.get(key)
        #expect(out == Data([1, 2, 3]))
    }

    @Test func differentMtimeIsCacheMiss() async throws {
        let (cache, root) = makeCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseKey = ThumbnailCacheKey(
            deviceID: DeviceID(raw: "DEV"),
            path: RemotePath(raw: "/x.jpg"),
            mtime: Date(timeIntervalSince1970: 1000),
            size: .medium
        )
        try await cache.put(baseKey, data: Data([1]))
        let newKey = ThumbnailCacheKey(
            deviceID: DeviceID(raw: "DEV"),
            path: RemotePath(raw: "/x.jpg"),
            mtime: Date(timeIntervalSince1970: 2000),
            size: .medium
        )
        let result = await cache.get(newKey)
        #expect(result == nil)
    }
}
