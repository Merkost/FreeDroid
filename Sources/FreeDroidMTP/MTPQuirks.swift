public struct MTPQuirks: Hashable, Sendable {
    public let maxWriteChunkBytes: Int
    public let requiresKeepalive: Bool
    public let keepaliveIntervalSeconds: Int

    public static let `default` = MTPQuirks(
        maxWriteChunkBytes: 1024 * 1024 * 1024,
        requiresKeepalive: false,
        keepaliveIntervalSeconds: 0
    )

    public static func `for`(vendorID: UInt16, productID: UInt16) -> MTPQuirks {
        switch vendorID {
        case 0x04E8:
            return MTPQuirks(
                maxWriteChunkBytes: 512 * 1024 * 1024,
                requiresKeepalive: false,
                keepaliveIntervalSeconds: 0
            )
        case 0x18D1:
            return MTPQuirks(
                maxWriteChunkBytes: 1024 * 1024 * 1024,
                requiresKeepalive: true,
                keepaliveIntervalSeconds: 45
            )
        default:
            return .default
        }
    }
}
