import Foundation
import Testing
import FreeDroidDomain
@testable import FreeDroidData

@Suite("ListingCache")
struct ListingCacheTests {
    private func entry(_ name: String) -> RemoteEntry {
        RemoteEntry(
            path: RemotePath(raw: "/sdcard/\(name)"),
            name: name,
            kind: .file,
            sizeBytes: 100,
            modifiedAt: nil,
            isHidden: false
        )
    }

    @Test func putThenGetReturnsValue() async {
        let cache = ListingCache(ttl: .seconds(60), capacity: 100)
        let key = ListingCacheKey(deviceID: DeviceID(raw: "A"), path: RemotePath(raw: "/x"))
        await cache.put(key: key, value: [entry("a")])
        let result = await cache.get(key)
        #expect(result?.count == 1)
    }

    @Test func ttlExpiry() async throws {
        let cache = ListingCache(ttl: .milliseconds(40), capacity: 100)
        let key = ListingCacheKey(deviceID: DeviceID(raw: "A"), path: RemotePath(raw: "/x"))
        await cache.put(key: key, value: [entry("a")])
        try await Task.sleep(for: .milliseconds(80))
        let result = await cache.get(key)
        #expect(result == nil)
    }

    @Test func invalidatePathRemovesEntry() async {
        let cache = ListingCache(ttl: .seconds(60), capacity: 100)
        let key = ListingCacheKey(deviceID: DeviceID(raw: "A"), path: RemotePath(raw: "/x"))
        await cache.put(key: key, value: [entry("a")])
        await cache.invalidate(deviceID: DeviceID(raw: "A"), path: RemotePath(raw: "/x"))
        let result = await cache.get(key)
        #expect(result == nil)
    }

    @Test func capacityEvictsOldest() async {
        let cache = ListingCache(ttl: .seconds(60), capacity: 2)
        for index in 0..<3 {
            let key = ListingCacheKey(deviceID: DeviceID(raw: "A"), path: RemotePath(raw: "/p\(index)"))
            await cache.put(key: key, value: [entry("e\(index)")])
        }
        let firstKey = ListingCacheKey(deviceID: DeviceID(raw: "A"), path: RemotePath(raw: "/p0"))
        let firstResult = await cache.get(firstKey)
        #expect(firstResult == nil)
    }
}
