public enum ADBDeviceState: String, Hashable, Sendable {
    case device
    case unauthorized
    case offline
    case noPermissions = "no permissions"
    case recovery
    case sideload
    case bootloader
    case unknown
}

public struct ADBDeviceListEntry: Hashable, Sendable {
    public let serial: String
    public let state: ADBDeviceState
    public let product: String?
    public let model: String?
    public let device: String?
    public let transportId: String?
}
