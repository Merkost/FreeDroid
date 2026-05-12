import Foundation

public enum IPCEndpoint {
    public static let appGroupIdentifier = "group.com.merkost.freedroid"
    public static let endpointFileName = "xpc-listener.endpoint"

    public static func endpointFileURL() -> URL? {
        groupContainerURL()?.appendingPathComponent(endpointFileName, isDirectory: false)
    }

    public static func groupContainerURL() -> URL? {
        if let sandboxedView = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return sandboxedView
        }
        let direct = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupIdentifier, isDirectory: true)
        return direct
    }

    public static func transferDirectory() -> URL {
        let base = groupContainerURL()?.appendingPathComponent("Transfers", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("FreeDroidTransfers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static func newTransferURL(filenameExtension ext: String) -> URL {
        let name = UUID().uuidString
        let url = transferDirectory().appendingPathComponent(name, isDirectory: false)
        return ext.isEmpty ? url : url.appendingPathExtension(ext)
    }
}
