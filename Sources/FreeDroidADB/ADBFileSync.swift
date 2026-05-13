import Foundation

public enum ADBFileSync {
    static let tempPrefix = "freedroid-adb-"
    static let bridgeTempPrefix = "freedroid-bridge-"
    static let staleTempThreshold: TimeInterval = 60 * 60

    static func tempLocalPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(tempPrefix + UUID().uuidString, isDirectory: false)
    }

    public static func purgeStaleTempFiles(now: Date = Date()) {
        let tempDir = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in entries {
            let name = url.lastPathComponent
            guard name.hasPrefix(tempPrefix) || name.hasPrefix(bridgeTempPrefix) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let mtime = values?.contentModificationDate else { continue }
            if now.timeIntervalSince(mtime) > staleTempThreshold {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
