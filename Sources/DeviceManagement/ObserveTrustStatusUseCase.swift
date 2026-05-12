public enum TrustStatus: Sendable, Hashable {
    case waiting
    case authorized
    case missing
    case error(String)
}

public protocol ObserveTrustStatusUseCase: Sendable {
    func callAsFunction(serial: String) -> AsyncStream<TrustStatus>
}
