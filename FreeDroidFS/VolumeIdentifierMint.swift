import Foundation
import FSKit
import CryptoKit

enum VolumeIdentifierMint {
    private static let namespace = UUID(uuidString: "8F4F9C7D-7B7E-4F1C-9D2F-31E2E12B7E08")!

    static func identifier(for deviceSerial: String) -> FSVolume.Identifier {
        let combined = "\(namespace.uuidString):\(deviceSerial)"
        let bytes = derivedUUIDBytes(from: combined)
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return FSVolume.Identifier(uuid: uuid)
    }

    private static func derivedUUIDBytes(from source: String) -> [UInt8] {
        let digest = SHA256.hash(data: Data(source.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes
    }
}
