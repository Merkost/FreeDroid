import Testing
@testable import FreeDroidDomain

@Suite("TransportError")
struct TransportErrorTests {
    @Test func isRetryableForTransientErrors() {
        #expect(TransportError.timeout(.seconds(1)).isRetryable)
        #expect(TransportError.ioFailure(message: "EAGAIN").isRetryable)
        #expect(TransportError.notConnected.isRetryable)
    }

    @Test func isNotRetryableForPermanentErrors() {
        #expect(!TransportError.unauthorized.isRetryable)
        #expect(!TransportError.notFound(RemotePath(raw: "/x")).isRetryable)
        #expect(!TransportError.alreadyExists(RemotePath(raw: "/x")).isRetryable)
        #expect(!TransportError.unsupported(reason: "no").isRetryable)
        #expect(!TransportError.cancelled.isRetryable)
    }
}
