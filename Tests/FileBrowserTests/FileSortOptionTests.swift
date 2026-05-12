import Foundation
import Testing
import FreeDroidDomain
@testable import FileBrowser

@Suite("FileSortOption")
struct FileSortOptionTests {
    private func entry(
        _ name: String,
        size: Int64? = nil,
        kind: EntryKind = .file,
        mtime: Date? = nil
    ) -> RemoteEntry {
        RemoteEntry(
            path: RemotePath(raw: "/x/\(name)"),
            name: name,
            kind: kind,
            sizeBytes: size,
            modifiedAt: mtime,
            isHidden: false
        )
    }

    @Test func nameAscendingFoldersFirst() {
        let entries = [entry("zebra.txt"), entry("apple", kind: .directory), entry("banana.txt")]
        let sorted = FileSortOption.name.apply(entries, ascending: true)
        #expect(sorted.map(\.name) == ["apple", "banana.txt", "zebra.txt"])
    }

    @Test func sizeDescending() {
        let entries = [entry("small", size: 100), entry("big", size: 1000), entry("med", size: 500)]
        let sorted = FileSortOption.size.apply(entries, ascending: false)
        #expect(sorted.map(\.name) == ["big", "med", "small"])
    }

    @Test func modifiedDescending() {
        let now = Date()
        let entries = [
            entry("old", mtime: now.addingTimeInterval(-3600)),
            entry("new", mtime: now),
            entry("mid", mtime: now.addingTimeInterval(-1800))
        ]
        let sorted = FileSortOption.modified.apply(entries, ascending: false)
        #expect(sorted.map(\.name) == ["new", "mid", "old"])
    }
}
