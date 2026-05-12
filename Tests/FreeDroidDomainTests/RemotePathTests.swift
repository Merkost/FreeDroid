import Testing
@testable import FreeDroidDomain

@Suite("RemotePath")
struct RemotePathTests {
    @Test func root() {
        let path = RemotePath.root
        #expect(path.raw == "/")
        #expect(path.isRoot)
    }

    @Test func appending() {
        let parent = RemotePath(raw: "/sdcard/DCIM")
        let child = parent.appending("Camera")
        #expect(child.raw == "/sdcard/DCIM/Camera")
    }

    @Test func appendingHandlesTrailingSlash() {
        let parent = RemotePath(raw: "/sdcard/")
        let child = parent.appending("DCIM")
        #expect(child.raw == "/sdcard/DCIM")
    }

    @Test func parent() {
        let path = RemotePath(raw: "/sdcard/DCIM/Camera")
        #expect(path.parent?.raw == "/sdcard/DCIM")
        #expect(RemotePath.root.parent == nil)
    }

    @Test func name() {
        #expect(RemotePath(raw: "/sdcard/DCIM/photo.jpg").name == "photo.jpg")
        #expect(RemotePath.root.name.isEmpty)
    }
}
