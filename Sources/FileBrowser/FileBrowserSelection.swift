import FreeDroidDomain

public struct FileBrowserSelection: Equatable, Sendable {
    public private(set) var paths: Set<RemotePath>
    public private(set) var anchor: RemotePath?

    public init(paths: Set<RemotePath> = [], anchor: RemotePath? = nil) {
        self.paths = paths
        self.anchor = anchor
    }

    public var count: Int { paths.count }
    public var isEmpty: Bool { paths.isEmpty }

    public mutating func toggle(_ path: RemotePath) {
        if paths.contains(path) {
            paths.remove(path)
        } else {
            paths.insert(path)
        }
        anchor = path
    }

    public mutating func replace(with path: RemotePath) {
        paths = [path]
        anchor = path
    }

    public mutating func replace(with newPaths: Set<RemotePath>, anchor newAnchor: RemotePath?) {
        paths = newPaths
        anchor = newAnchor
    }

    public mutating func clear() {
        paths.removeAll()
        anchor = nil
    }

    public func contains(_ path: RemotePath) -> Bool {
        paths.contains(path)
    }
}
