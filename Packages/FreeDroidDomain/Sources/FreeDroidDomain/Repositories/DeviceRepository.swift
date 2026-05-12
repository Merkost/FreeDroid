public protocol DeviceRepository: Sendable {
    func observe() -> AsyncStream<[Device]>
    func device(_ id: DeviceID) async -> Device?
}
