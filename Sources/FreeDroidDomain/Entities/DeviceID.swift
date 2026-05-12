public struct DeviceID: Hashable, Sendable, Codable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }
}
