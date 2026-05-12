import FreeDroidDomain

public enum IPCError: Codable, Sendable, Equatable {
    case transport(TransportError)
    case noTransport
    case decodingFailed(String)
}
