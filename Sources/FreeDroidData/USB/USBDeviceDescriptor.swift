public struct USBDeviceDescriptor: Hashable, Sendable {
    public let vendorID: UInt16
    public let productID: UInt16
    public let serialNumber: String?
    public let vendorName: String?
    public let productName: String?
    public let locationID: UInt32
}
