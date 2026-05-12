public struct Device: Identifiable, Hashable, Sendable, Codable {
    public let id: DeviceID
    public let displayName: String
    public let manufacturer: String
    public let model: String
    public let storageCapacityBytes: Int64?
    public let storageFreeBytes: Int64?
    public let transport: TransportKind

    public init(
        id: DeviceID,
        displayName: String,
        manufacturer: String,
        model: String,
        storageCapacityBytes: Int64?,
        storageFreeBytes: Int64?,
        transport: TransportKind
    ) {
        self.id = id
        self.displayName = displayName
        self.manufacturer = manufacturer
        self.model = model
        self.storageCapacityBytes = storageCapacityBytes
        self.storageFreeBytes = storageFreeBytes
        self.transport = transport
    }
}
