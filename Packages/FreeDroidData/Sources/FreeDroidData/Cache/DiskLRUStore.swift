import Foundation
import CryptoKit

public actor DiskLRUStore {
    private let rootURL: URL
    private let capacityBytes: Int64
    private let fileManager: FileManager

    public init(rootURL: URL, capacityBytes: Int64, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.capacityBytes = capacityBytes
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func get(_ key: String) async -> Data? {
        let fileURL = url(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try? touch(fileURL)
        return try? Data(contentsOf: fileURL)
    }

    public func put(_ key: String, data: Data) async throws {
        let fileURL = url(for: key)
        try data.write(to: fileURL, options: [.atomic])
        try await trimIfNeeded()
    }

    public func remove(_ key: String) async {
        try? fileManager.removeItem(at: url(for: key))
    }

    public func clear() async {
        try? fileManager.removeItem(at: rootURL)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        let digest = Insecure.SHA1.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(hex)
    }

    private func touch(_ fileURL: URL) throws {
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    private func trimIfNeeded() async throws {
        let total = try totalSize()
        guard total > capacityBytes else { return }
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        let sorted = try urls.sorted { lhs, rhs in
            let modKeys: Set<URLResourceKey> = [.contentModificationDateKey]
            let leftDate = try lhs.resourceValues(forKeys: modKeys).contentModificationDate ?? .distantPast
            let rightDate = try rhs.resourceValues(forKeys: modKeys).contentModificationDate ?? .distantPast
            return leftDate < rightDate
        }
        var freed: Int64 = 0
        let mustFree = total - capacityBytes
        for fileURL in sorted {
            guard freed < mustFree else { break }
            if let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                try? fileManager.removeItem(at: fileURL)
                freed += Int64(size)
            }
        }
    }

    private func totalSize() throws -> Int64 {
        let urls = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        for fileURL in urls {
            if let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
