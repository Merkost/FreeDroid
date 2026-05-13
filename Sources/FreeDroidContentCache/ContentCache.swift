import Foundation
import CryptoKit

private struct CacheEntryMeta: Codable {
    let version: String
    let keyDescription: String
    let fetchedAt: Date
    var lastAccessedAt: Date
    let size: Int64
    let deviceID: String
    let path: String
    let mtimeUnix: Int64
    let keySizeBytes: Int64
}

public actor ContentCache {
    private let rootURL: URL
    private let capacityBytes: Int64
    private let fileManager: FileManager

    public init(
        rootURL: URL = ContentCache.defaultRoot,
        capacityBytes: Int64 = 10 * 1024 * 1024 * 1024
    ) {
        self.rootURL = rootURL
        self.capacityBytes = capacityBytes
        self.fileManager = FileManager()
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public static var defaultRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("FreeDroid/Content", isDirectory: true)
    }

    public func lookup(_ key: ContentKey) -> URL? {
        let entryDir = entryDirectory(for: key)
        let metaURL = entryDir.appendingPathComponent("meta.json")
        guard var meta = readMeta(at: metaURL) else { return nil }
        guard meta.deviceID == key.deviceID,
              meta.path == key.path,
              meta.mtimeUnix == key.mtimeUnix,
              meta.keySizeBytes == key.size else {
            return nil
        }
        let contents = (try? fileManager.contentsOfDirectory(
            at: entryDir,
            includingPropertiesForKeys: nil
        )) ?? []
        let fileURL = contents.first { $0.lastPathComponent != "meta.json" }
        guard let fileURL, fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let now = Date()
        if now.timeIntervalSince(meta.lastAccessedAt) > 60 {
            meta.lastAccessedAt = now
            writeMeta(meta, to: metaURL)
        }
        return fileURL
    }

    private func readMeta(at url: URL) -> CacheEntryMeta? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CacheEntryMeta.self, from: data)
    }

    private func writeMeta(_ meta: CacheEntryMeta, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(meta) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    public func store(_ source: URL, key: ContentKey, filename: String) async throws -> URL {
        let entryDir = entryDirectory(for: key)
        try fileManager.createDirectory(at: entryDir, withIntermediateDirectories: true)

        let destURL = entryDir.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }

        do {
            try fileManager.linkItem(at: source, to: destURL)
        } catch {
            try fileManager.copyItem(at: source, to: destURL)
        }

        let now = Date()
        let meta = CacheEntryMeta(
            version: "v1",
            keyDescription: "\(key.deviceID)|\(key.path)|\(key.mtimeUnix)|\(key.size)",
            fetchedAt: now,
            lastAccessedAt: now,
            size: key.size,
            deviceID: key.deviceID,
            path: key.path,
            mtimeUnix: key.mtimeUnix,
            keySizeBytes: key.size
        )
        let metaURL = entryDir.appendingPathComponent("meta.json")
        writeMeta(meta, to: metaURL)

        await trimIfNeeded()

        return destURL
    }

    public func evict(matching predicate: (ContentKey) -> Bool) async {
        let deviceDirs = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )) ?? []
        for deviceDir in deviceDirs {
            let entryDirs = (try? fileManager.contentsOfDirectory(
                at: deviceDir,
                includingPropertiesForKeys: nil
            )) ?? []
            for entryDir in entryDirs {
                guard let key = readKey(from: entryDir), predicate(key) else { continue }
                try? fileManager.removeItem(at: entryDir)
            }
            let remaining = (try? fileManager.contentsOfDirectory(
                at: deviceDir,
                includingPropertiesForKeys: nil
            )) ?? []
            if remaining.isEmpty {
                try? fileManager.removeItem(at: deviceDir)
            }
        }
    }

    public func evictAll() async {
        try? fileManager.removeItem(at: rootURL)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func totalSizeBytes() -> Int64 {
        computeTotalSize()
    }

    private func entryDirectory(for key: ContentKey) -> URL {
        rootURL
            .appendingPathComponent(Self.sha256Hex(key.deviceID), isDirectory: true)
            .appendingPathComponent(key.sha256Hex, isDirectory: true)
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func readKey(from entryDir: URL) -> ContentKey? {
        let metaURL = entryDir.appendingPathComponent("meta.json")
        guard let meta = readMeta(at: metaURL) else { return nil }
        return ContentKey(
            deviceID: meta.deviceID,
            path: meta.path,
            mtimeUnix: meta.mtimeUnix,
            size: meta.keySizeBytes
        )
    }

    private func computeTotalSize() -> Int64 {
        var total: Int64 = 0
        let deviceDirs = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        for deviceDir in deviceDirs {
            let entryDirs = (try? fileManager.contentsOfDirectory(
                at: deviceDir,
                includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            for entryDir in entryDirs {
                let files = (try? fileManager.contentsOfDirectory(
                    at: entryDir,
                    includingPropertiesForKeys: [.fileSizeKey]
                )) ?? []
                for file in files {
                    if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            }
        }
        return total
    }

    private func trimIfNeeded() async {
        let total = computeTotalSize()
        guard total > capacityBytes else { return }

        struct EntryRecord {
            let dir: URL
            let lastAccessedAt: Date
            let size: Int64
        }

        var records: [EntryRecord] = []
        let deviceDirs = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )) ?? []
        for deviceDir in deviceDirs {
            let entryDirs = (try? fileManager.contentsOfDirectory(
                at: deviceDir,
                includingPropertiesForKeys: nil
            )) ?? []
            for entryDir in entryDirs {
                guard let meta = readMeta(at: entryDir.appendingPathComponent("meta.json")) else { continue }
                let entrySize = computeEntrySize(at: entryDir)
                records.append(EntryRecord(dir: entryDir, lastAccessedAt: meta.lastAccessedAt, size: entrySize))
            }
        }

        records.sort { $0.lastAccessedAt < $1.lastAccessedAt }
        var freed: Int64 = 0
        let mustFree = total - capacityBytes
        for record in records {
            guard freed < mustFree else { break }
            try? fileManager.removeItem(at: record.dir)
            freed += record.size
        }
    }

    private func computeEntrySize(at entryDir: URL) -> Int64 {
        var entrySize: Int64 = 0
        let files = (try? fileManager.contentsOfDirectory(
            at: entryDir,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        for file in files {
            if let sz = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                entrySize += Int64(sz)
            }
        }
        return entrySize
    }
}
