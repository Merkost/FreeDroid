public enum DeviceConnectionState: String, Hashable, Sendable, Codable {
    case ready
    case pendingAuthorization
    case chargingOnly
}

public struct Device: Identifiable, Hashable, Sendable, Codable {
    public let id: DeviceID
    public let displayName: String
    public let manufacturer: String
    public let model: String
    public let storageCapacityBytes: Int64?
    public let storageFreeBytes: Int64?
    public let transport: TransportKind
    public let connectionState: DeviceConnectionState

    public init(
        id: DeviceID,
        displayName: String,
        manufacturer: String,
        model: String,
        storageCapacityBytes: Int64?,
        storageFreeBytes: Int64?,
        transport: TransportKind,
        connectionState: DeviceConnectionState = .ready
    ) {
        self.id = id
        self.displayName = displayName
        self.manufacturer = manufacturer
        self.model = model
        self.storageCapacityBytes = storageCapacityBytes
        self.storageFreeBytes = storageFreeBytes
        self.transport = transport
        self.connectionState = connectionState
    }
}
