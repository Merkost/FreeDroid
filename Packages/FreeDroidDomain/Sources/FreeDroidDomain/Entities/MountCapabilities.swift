public struct MountCapabilities: Hashable, Sendable, Codable {
    public let supportsTrueMount: Bool
    public let supportsWriteOps: Bool
    public let appearsInFinderSidebar: Bool

    public init(supportsTrueMount: Bool, supportsWriteOps: Bool, appearsInFinderSidebar: Bool) {
        self.supportsTrueMount = supportsTrueMount
        self.supportsWriteOps = supportsWriteOps
        self.appearsInFinderSidebar = appearsInFinderSidebar
    }
}
