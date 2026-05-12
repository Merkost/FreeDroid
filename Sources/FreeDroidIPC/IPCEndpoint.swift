import Foundation

public enum IPCEndpoint {
    public static let appGroupIdentifier = "group.com.merkost.freedroid"
    public static let endpointFileName = "xpc-listener.endpoint"

    public static func endpointFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(endpointFileName, isDirectory: false)
    }
}
