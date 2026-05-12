import Foundation
import CryptoKit

public struct ContentKey: Hashable, Sendable {
    public let deviceID: String
    public let path: String
    public let mtimeUnix: Int64
    public let size: Int64

    public init(deviceID: String, path: String, mtimeUnix: Int64, size: Int64) {
        self.deviceID = deviceID
        self.path = path
        self.mtimeUnix = mtimeUnix
        self.size = size
    }

    public var sha256Hex: String {
        let input = "\(deviceID)|\(path)|\(mtimeUnix)|\(size)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
