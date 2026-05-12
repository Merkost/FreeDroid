import FreeDroidDomain

public enum ADBWireError: Error, Sendable {
    case okayExpected(got: String)
    case syncFailed(String)
    case socketClosed
    case framingViolation(context: String, firstBytes: [UInt8])

    public var asTransportError: TransportError {
        switch self {
        case .okayExpected(let got):
            return .ioFailure(message: "ADB expected OKAY, got: \(got)")
        case .syncFailed(let msg):
            return .ioFailure(message: "ADB sync failed: \(msg)")
        case .socketClosed:
            return .notConnected
        case .framingViolation(let context, let bytes):
            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            return .ioFailure(message: "ADB wire framing violation [\(context)] first bytes: \(hex)")
        }
    }
}
