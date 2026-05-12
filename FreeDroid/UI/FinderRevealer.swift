import Foundation
import AppKit

@MainActor
enum FinderRevealer {
    static func revealTransferDestination(for deviceName: String) {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let safeName = deviceName.replacingOccurrences(of: "/", with: "-")
        let folder = base.appendingPathComponent("FreeDroid/\(safeName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
