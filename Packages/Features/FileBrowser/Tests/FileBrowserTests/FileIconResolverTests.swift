import Testing
import FreeDroidDomain
@testable import FileBrowser

@Suite("FileIconResolver")
struct FileIconResolverTests {
    @Test func directoryIcon() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/x/DCIM"),
            name: "DCIM",
            kind: .directory,
            sizeBytes: nil,
            modifiedAt: nil,
            isHidden: false
        )
        #expect(FileIconResolver.symbol(for: entry) == "folder")
    }

    @Test func imageIcon() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/x/a.jpg"),
            name: "a.jpg",
            kind: .file,
            sizeBytes: 1,
            modifiedAt: nil,
            isHidden: false
        )
        #expect(FileIconResolver.symbol(for: entry) == "photo")
    }

    @Test func videoIcon() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/x/a.mp4"),
            name: "a.mp4",
            kind: .file,
            sizeBytes: 1,
            modifiedAt: nil,
            isHidden: false
        )
        #expect(FileIconResolver.symbol(for: entry) == "play.rectangle")
    }

    @Test func documentIcon() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/x/a.pdf"),
            name: "a.pdf",
            kind: .file,
            sizeBytes: 1,
            modifiedAt: nil,
            isHidden: false
        )
        #expect(FileIconResolver.symbol(for: entry) == "doc.richtext")
    }

    @Test func defaultIcon() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/x/a.weird"),
            name: "a.weird",
            kind: .file,
            sizeBytes: 1,
            modifiedAt: nil,
            isHidden: false
        )
        #expect(FileIconResolver.symbol(for: entry) == "doc")
    }
}
