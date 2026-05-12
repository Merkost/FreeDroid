import Foundation
import FreeDroidDomain

actor FreeDroidItemCache {
    private struct CacheEntry {
        let item: FreeDroidItem
        let storedAt: ContinuousClock.Instant
    }

    private let ttl: Duration
    private let clock = ContinuousClock()
    private var entries: [RemotePath: CacheEntry] = [:]

    init(ttl: Duration = .seconds(45)) {
        self.ttl = ttl
    }

    func get(_ path: RemotePath) -> FreeDroidItem? {
        guard let entry = entries[path] else { return nil }
        guard clock.now - entry.storedAt <= ttl else {
            entries[path] = nil
            return nil
        }
        return entry.item
    }

    func put(_ path: RemotePath, _ item: FreeDroidItem) {
        entries[path] = CacheEntry(item: item, storedAt: clock.now)
    }

    func invalidate(_ path: RemotePath) {
        entries[path] = nil
        let prefix = path.raw + "/"
        for key in entries.keys where key.raw.hasPrefix(prefix) {
            entries[key] = nil
        }
    }

    func invalidateAll() {
        entries.removeAll()
    }
}
