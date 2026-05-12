import FreeDroidDomain

public struct DeviceRecord: Sendable {
    public let device: Device
    public let transport: (any Transport)?

    public init(device: Device, transport: (any Transport)?) {
        self.device = device
        self.transport = transport
    }
}
