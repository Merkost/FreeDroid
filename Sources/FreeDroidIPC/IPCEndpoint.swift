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
}
