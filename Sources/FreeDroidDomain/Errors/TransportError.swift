import Foundation

public enum TransportError: Hashable, Sendable, Error, Codable {
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

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable {
        case notConnected, unauthorized, timeout, ioFailure, notFound, alreadyExists, unsupported, cancelled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .notConnected: self = .notConnected
        case .unauthorized: self = .unauthorized
        case .timeout:
            let seconds = try container.decode(Double.self, forKey: .payload)
            self = .timeout(.seconds(seconds))
        case .ioFailure:
            let message = try container.decode(String.self, forKey: .payload)
            self = .ioFailure(message: message)
        case .notFound:
            let path = try container.decode(RemotePath.self, forKey: .payload)
            self = .notFound(path)
        case .alreadyExists:
            let path = try container.decode(RemotePath.self, forKey: .payload)
            self = .alreadyExists(path)
        case .unsupported:
            let reason = try container.decode(String.self, forKey: .payload)
            self = .unsupported(reason: reason)
        case .cancelled: self = .cancelled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notConnected: try container.encode(Kind.notConnected, forKey: .kind)
        case .unauthorized: try container.encode(Kind.unauthorized, forKey: .kind)
        case .timeout(let duration):
            try container.encode(Kind.timeout, forKey: .kind)
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            try container.encode(seconds, forKey: .payload)
        case .ioFailure(let message):
            try container.encode(Kind.ioFailure, forKey: .kind)
            try container.encode(message, forKey: .payload)
        case .notFound(let path):
            try container.encode(Kind.notFound, forKey: .kind)
            try container.encode(path, forKey: .payload)
        case .alreadyExists(let path):
            try container.encode(Kind.alreadyExists, forKey: .kind)
            try container.encode(path, forKey: .payload)
        case .unsupported(let reason):
            try container.encode(Kind.unsupported, forKey: .kind)
            try container.encode(reason, forKey: .payload)
        case .cancelled: try container.encode(Kind.cancelled, forKey: .kind)
        }
    }
}
