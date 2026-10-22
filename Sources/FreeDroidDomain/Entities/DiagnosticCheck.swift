import Foundation

public struct DiagnosticCheck: Identifiable, Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case passed
        case warning
        case failed
    }

    public let id: String
    public let title: String
    public let detail: String
    public let status: Status

    public init(id: String, title: String, detail: String, status: Status) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
    }
}
