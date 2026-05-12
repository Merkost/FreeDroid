public struct MTPRawDevice: Hashable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let busLocation: UInt32
    public let devnum: UInt8
    public let vendorName: String?
    public let productName: String?

    public var identifier: String {
        "USB-\(busLocation)-\(devnum)-\(vendorID)-\(productID)"
    }
}
