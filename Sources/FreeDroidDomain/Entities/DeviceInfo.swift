public struct DeviceInfo: Hashable, Sendable, Codable {
    public let serial: String
    public let manufacturer: String
    public let model: String
    public let androidVersion: String?
    public let storageCapacityBytes: Int64?
    public let storageFreeBytes: Int64?

    public init(
        serial: String,
        manufacturer: String,
        model: String,
        androidVersion: String?,
        storageCapacityBytes: Int64?,
        storageFreeBytes: Int64?
    ) {
        self.serial = serial
        self.manufacturer = manufacturer
        self.model = model
        self.androidVersion = androidVersion
        self.storageCapacityBytes = storageCapacityBytes
        self.storageFreeBytes = storageFreeBytes
    }
}
