import Foundation

enum ADBFileSync {
    static func tempLocalPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("freedroid-adb-\(UUID().uuidString)", isDirectory: false)
    }
}
