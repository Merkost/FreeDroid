import Testing
import Foundation
import FreeDroidDomain
@testable import FreeDroidMTP

@Suite("MTPPathResolver")
struct MTPPathResolverTests {
    private func sampleObjects() -> [MTPObject] {
        [
            MTPObject(
                storageID: 1, objectHandle: 100, parentHandle: 0,
                name: "DCIM", isFolder: true, size: 0, modifiedAt: nil
            ),
            MTPObject(
                storageID: 1, objectHandle: 200, parentHandle: 100,
                name: "Camera", isFolder: true, size: 0, modifiedAt: nil
            ),
            MTPObject(
                storageID: 1, objectHandle: 300, parentHandle: 200,
                name: "IMG_001.jpg", isFolder: false, size: 1024, modifiedAt: nil
            )
        ]
    }

    @Test func resolveFolderPath() {
        let resolver = MTPPathResolver(objects: sampleObjects())
        let handle = resolver.handle(for: RemotePath(raw: "/DCIM/Camera"))
        #expect(handle == 200)
    }

    @Test func resolveFilePath() {
        let resolver = MTPPathResolver(objects: sampleObjects())
        let handle = resolver.handle(for: RemotePath(raw: "/DCIM/Camera/IMG_001.jpg"))
        #expect(handle == 300)
    }

    @Test func resolveRoot() {
        let resolver = MTPPathResolver(objects: sampleObjects())
        let handle = resolver.handle(for: RemotePath(raw: "/"))
        #expect(handle == 0)
    }

    @Test func resolveMissingPathReturnsNil() {
        let resolver = MTPPathResolver(objects: sampleObjects())
        let handle = resolver.handle(for: RemotePath(raw: "/DCIM/NotThere"))
        #expect(handle == nil)
    }

    @Test func listChildren() {
        let resolver = MTPPathResolver(objects: sampleObjects())
        let children = resolver.children(of: RemotePath(raw: "/DCIM"))
        #expect(children.count == 1)
        #expect(children.first?.name == "Camera")
    }
}
