import FreeDroidDomain

public enum MTPSessionError: Hashable, Sendable, Error {
    case notInitialized
    case noDevicesFound
    case openFailed(message: String)
    case operationFailed(message: String)
    case unsupportedFeature(String)

    public func toTransportError() -> TransportError {
        switch self {
        case .notInitialized: .notConnected
        case .noDevicesFound: .notConnected
        case .openFailed(let msg): .ioFailure(message: "open: \(msg)")
        case .operationFailed(let msg): .ioFailure(message: msg)
        case .unsupportedFeature(let s): .unsupported(reason: s)
        }
    }
}
