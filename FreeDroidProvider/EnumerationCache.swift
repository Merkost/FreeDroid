import Foundation
import FreeDroidProviderShared

actor EnumerationCache {
    private struct Entry {
        let value: RemoteEntry
        let storedAt: ContinuousClock.Instant
    }

    private let ttl: Duration = .seconds(30)
    private let clock = ContinuousClock()
    private var entries: [RemotePath: Entry] = [:]

    func record(_ values: [RemoteEntry]) {
        let now = clock.now
        for entry in values {
            entries[entry.path] = Entry(value: entry, storedAt: now)
        }
    }

    func lookup(_ path: RemotePath) -> RemoteEntry? {
        guard let entry = entries[path] else { return nil }
        if (clock.now - entry.storedAt) > ttl {
            entries[path] = nil
            return nil
        }
        return entry.value
    }

    func invalidate(_ path: RemotePath) {
        entries[path] = nil
    }
}
