import Foundation

public protocol TransferDestinationProvider: Sendable {
    func destinationForDevice(_ deviceName: String) -> URL
}

public struct DownloadsTransferDestinationProvider: TransferDestinationProvider {
    public init() {}

    public func destinationForDevice(_ deviceName: String) -> URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let safe = deviceName.replacingOccurrences(of: "/", with: "-")
        let folder = base.appendingPathComponent("FreeDroid/\(safe)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
