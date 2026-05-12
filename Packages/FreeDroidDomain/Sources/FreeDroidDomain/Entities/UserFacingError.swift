public enum RecoveryAction: Hashable, Sendable, Codable {
    case retry
    case openSettings
    case authorizeOnDevice
    case contactSupport
}

public struct UserFacingError: Hashable, Sendable, Codable, Error {
    public let title: String
    public let message: String
    public let recoveryAction: RecoveryAction?

    public init(title: String, message: String, recoveryAction: RecoveryAction?) {
        self.title = title
        self.message = message
        self.recoveryAction = recoveryAction
    }
}
