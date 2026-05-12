import Foundation

public enum TransportError: Hashable, Sendable, Error {
    case notConnected
    case unauthorized
    case timeout(Duration)
    case ioFailure(message: String)
    case notFound(RemotePath)
    case alreadyExists(RemotePath)
    case unsupported(reason: String)
    case cancelled

    public var isRetryable: Bool {
        switch self {
        case .timeout, .ioFailure, .notConnected: true
        case .unauthorized, .notFound, .alreadyExists, .unsupported, .cancelled: false
        }
    }
}
