public protocol MountStrategy: Sendable {
    var capabilities: MountCapabilities { get }
    func mount(_ device: Device, transport: any Transport) async throws -> MountedVolume
    func unmount(_ volume: MountedVolume) async throws
}
