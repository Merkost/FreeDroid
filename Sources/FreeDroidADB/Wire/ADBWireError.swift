import FreeDroidDomain

public enum ADBWireError: Error, Sendable {
    case okayExpected(got: String)
    case syncFailed(String)
    case socketClosed
    case framingViolation

    public var asTransportError: TransportError {
        switch self {
        case .okayExpected(let got):
            return .ioFailure(message: "ADB expected OKAY, got: \(got)")
        case .syncFailed(let msg):
            return .ioFailure(message: "ADB sync failed: \(msg)")
        case .socketClosed:
            return .notConnected
        case .framingViolation:
            return .ioFailure(message: "ADB wire protocol framing violation")
        }
    }
}
