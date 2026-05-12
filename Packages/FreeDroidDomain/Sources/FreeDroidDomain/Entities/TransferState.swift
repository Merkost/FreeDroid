public enum TransferState: Hashable, Sendable {
    case idle
    case running(TransferProgress)
    case paused(TransferProgress)
    case completed
    case failed(TransportError)
}
