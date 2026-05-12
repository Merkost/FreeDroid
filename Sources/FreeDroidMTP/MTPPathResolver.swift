import Foundation
import FreeDroidDomain

public struct MTPPathResolver: Sendable {
    public let objects: [MTPObject]
    private let byHandle: [UInt32: MTPObject]
    private let childrenByParent: [UInt32: [MTPObject]]

    public init(objects: [MTPObject]) {
        self.objects = objects
        self.byHandle = Dictionary(uniqueKeysWithValues: objects.map { ($0.objectHandle, $0) })
        self.childrenByParent = Dictionary(grouping: objects, by: { $0.parentHandle })
    }

    public func handle(for path: RemotePath) -> UInt32? {
        guard !path.isRoot else { return 0 }
        let components = path.raw
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        var currentParent: UInt32 = 0
        for component in components {
            guard let child = (childrenByParent[currentParent] ?? []).first(where: { $0.name == component }) else {
                return nil
            }
            currentParent = child.objectHandle
        }
        return currentParent
    }

    public func children(of path: RemotePath) -> [MTPObject] {
        let parent = handle(for: path) ?? 0
        return childrenByParent[parent] ?? []
    }
}
