public struct RemotePath: Hashable, Sendable, Codable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    public static let root = RemotePath(raw: "/")

    public var isRoot: Bool {
        raw == "/"
    }

    public var parent: RemotePath? {
        guard !isRoot else { return nil }
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return .root }
        let parentRaw = String(trimmed[..<lastSlash])
        return parentRaw.isEmpty ? .root : RemotePath(raw: parentRaw)
    }

    public var name: String {
        guard !isRoot else { return "" }
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: lastSlash)...])
    }

    public func appending(_ component: String) -> RemotePath {
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        return RemotePath(raw: base + "/" + component)
    }
}
