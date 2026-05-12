import Foundation

@objc public protocol XPCFileServerProtocol: Sendable {
    func send(_ payload: Data) async -> Data
}

public enum XPCService {
    public static let bundleIdentifier = "com.merkost.freedroid.FreeDroidBridge"
}
