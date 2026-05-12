import Foundation
import FreeDroidDomain

public struct ListingCacheKey: Hashable, Sendable {
    public let deviceID: DeviceID
    public let path: RemotePath

    public init(deviceID: DeviceID, path: RemotePath) {
        self.deviceID = deviceID
        self.path = path
    }
}

public actor ListingCache: Cache {
    public typealias Key = ListingCacheKey
    public typealias Value = [RemoteEntry]

    private struct Entry {
        let value: [RemoteEntry]
        let storedAt: ContinuousClock.Instant
    }

    private let ttl: Duration
    private let capacity: Int
    private let clock = ContinuousClock()
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []

    public init(ttl: Duration = .seconds(60), capacity: Int = 1000) {
        self.ttl = ttl
        self.capacity = capacity
    }

    public func get(_ key: Key) async -> [RemoteEntry]? {
        guard let entry = entries[key] else { return nil }
        if (clock.now - entry.storedAt) > ttl {
            entries[key] = nil
            order.removeAll { $0 == key }
            return nil
        }
        return entry.value
    }

    public func put(key: Key, value: [RemoteEntry]) async {
        if entries[key] != nil {
            order.removeAll { $0 == key }
        }
        entries[key] = Entry(value: value, storedAt: clock.now)
        order.append(key)
        while order.count > capacity {
            let oldest = order.removeFirst()
            entries[oldest] = nil
        }
    }

    public func remove(_ key: Key) async {
        entries[key] = nil
        order.removeAll { $0 == key }
    }

    public func clear() async {
        entries.removeAll()
        order.removeAll()
    }

    public func invalidate(deviceID: DeviceID, path: RemotePath) async {
        await remove(ListingCacheKey(deviceID: deviceID, path: path))
    }

    public func invalidateAll(for deviceID: DeviceID) async {
        let keys = entries.keys.filter { $0.deviceID == deviceID }
        for key in keys {
            await remove(key)
        }
    }
}
