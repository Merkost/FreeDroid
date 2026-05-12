import Foundation
import Testing
@testable import FreeDroidContentCache

@Suite("ContentCache")
struct ContentCacheTests {

    private func makeCache(capacity: Int64 = 10 * 1024 * 1024 * 1024) async -> ContentCache {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeDroidContentCacheTests-\(UUID().uuidString)")
        return ContentCache(rootURL: tmp, capacityBytes: capacity)
    }

    private func makeTempFile(content: Data, name: String = "test.bin") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeDroidContentCacheTests-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }

    @Test("lookup miss then store then hit")
    func lookupMissThenStoreThenHit() async throws {
        let cache = await makeCache()
        let key = ContentKey(deviceID: "device1", path: "/foo/bar.txt", mtimeUnix: 1000, size: 5)
        let miss = await cache.lookup(key)
        #expect(miss == nil)

        let source = try makeTempFile(content: Data("hello".utf8), name: "bar.txt")
        let stored = try await cache.store(source, key: key, filename: "bar.txt")
        #expect(FileManager.default.fileExists(atPath: stored.path))

        let hit = await cache.lookup(key)
        #expect(hit != nil)
        let data = try Data(contentsOf: hit!)
        #expect(data == Data("hello".utf8))
    }

    @Test("mtime change invalidates entry")
    func mtimeChangeInvalidatesEntry() async throws {
        let cache = await makeCache()
        let key1 = ContentKey(deviceID: "device1", path: "/foo/bar.txt", mtimeUnix: 1000, size: 5)
        let source = try makeTempFile(content: Data("hello".utf8), name: "bar.txt")
        _ = try await cache.store(source, key: key1, filename: "bar.txt")

        let key2 = ContentKey(deviceID: "device1", path: "/foo/bar.txt", mtimeUnix: 2000, size: 5)
        let hit = await cache.lookup(key2)
        #expect(hit == nil)
    }

    @Test("LRU eviction at capacity")
    func lruEvictionAtCapacity() async throws {
        let payloadSize = 1024
        let capacity = Int64(payloadSize * 2)
        let cache = await makeCache(capacity: capacity)

        let data1 = Data(repeating: 0xAA, count: payloadSize)
        let data2 = Data(repeating: 0xBB, count: payloadSize)
        let data3 = Data(repeating: 0xCC, count: payloadSize)

        let src1 = try makeTempFile(content: data1, name: "a.bin")
        let src2 = try makeTempFile(content: data2, name: "b.bin")
        let src3 = try makeTempFile(content: data3, name: "c.bin")

        let key1 = ContentKey(deviceID: "dev", path: "/a.bin", mtimeUnix: 1, size: Int64(payloadSize))
        let key2 = ContentKey(deviceID: "dev", path: "/b.bin", mtimeUnix: 1, size: Int64(payloadSize))
        let key3 = ContentKey(deviceID: "dev", path: "/c.bin", mtimeUnix: 1, size: Int64(payloadSize))

        _ = try await cache.store(src1, key: key1, filename: "a.bin")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await cache.store(src2, key: key2, filename: "b.bin")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await cache.store(src3, key: key3, filename: "c.bin")

        let total = await cache.totalSizeBytes()
        #expect(total <= capacity)

        let hitKey3 = await cache.lookup(key3)
        #expect(hitKey3 != nil)

        let hitKey1 = await cache.lookup(key1)
        #expect(hitKey1 == nil)
    }

    @Test("evict matching path")
    func evictMatchingPath() async throws {
        let cache = await makeCache()
        let key1 = ContentKey(deviceID: "dev", path: "/foo.txt", mtimeUnix: 1, size: 3)
        let key2 = ContentKey(deviceID: "dev", path: "/bar.txt", mtimeUnix: 1, size: 3)

        let src1 = try makeTempFile(content: Data("foo".utf8), name: "foo.txt")
        let src2 = try makeTempFile(content: Data("bar".utf8), name: "bar.txt")

        _ = try await cache.store(src1, key: key1, filename: "foo.txt")
        _ = try await cache.store(src2, key: key2, filename: "bar.txt")

        await cache.evict { $0.path == "/foo.txt" && $0.deviceID == "dev" }

        let hitFoo = await cache.lookup(key1)
        let hitBar = await cache.lookup(key2)
        #expect(hitFoo == nil)
        #expect(hitBar != nil)
    }

    @Test("concurrent lookups and stores")
    func concurrentLookupsAndStores() async throws {
        let cache = await makeCache()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let key = ContentKey(
                        deviceID: "dev",
                        path: "/file\(i).bin",
                        mtimeUnix: Int64(i),
                        size: 4
                    )
                    let src = try FileManager.default.temporaryDirectory
                        .appendingPathComponent("cct-src-\(UUID().uuidString).bin")
                    try Data(repeating: UInt8(i % 256), count: 4).write(to: src)
                    _ = try await cache.store(src, key: key, filename: "file\(i).bin")
                    let hit = await cache.lookup(key)
                    #expect(hit != nil)
                }
            }
            try await group.waitForAll()
        }
        let total = await cache.totalSizeBytes()
        #expect(total > 0)
    }
}
