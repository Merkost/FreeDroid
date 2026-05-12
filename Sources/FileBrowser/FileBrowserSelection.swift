import FreeDroidDomain

public struct FileBrowserSelection: Equatable, Sendable {
    public private(set) var paths: Set<RemotePath>

    public init(paths: Set<RemotePath> = []) {
        self.paths = paths
    }

    public var count: Int { paths.count }
    public var isEmpty: Bool { paths.isEmpty }

    public mutating func toggle(_ path: RemotePath) {
        if paths.contains(path) {
            paths.remove(path)
        } else {
            paths.insert(path)
        }
    }

    public mutating func replace(with path: RemotePath) {
        paths = [path]
    }

    public mutating func clear() {
        paths.removeAll()
    }

    public func contains(_ path: RemotePath) -> Bool {
        paths.contains(path)
    }
}
