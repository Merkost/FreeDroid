import XCTest
import FileProvider
import UniformTypeIdentifiers
@testable import FreeDroidProviderShared

final class ProviderItemTests: XCTestCase {
    func testRootItem() {
        let item = ProviderItem.root(displayName: "Pixel 9")
        XCTAssertEqual(item.itemIdentifier, .rootContainer)
        XCTAssertEqual(item.parentItemIdentifier, .rootContainer)
        XCTAssertEqual(item.filename, "Pixel 9")
        XCTAssertEqual(item.contentType, .folder)
    }

    func testFolderFromEntry() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/sdcard/DCIM"),
            name: "DCIM",
            kind: .directory,
            sizeBytes: nil,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isHidden: false
        )
        let item = ProviderItem(entry: entry, parent: .root)
        XCTAssertEqual(item.filename, "DCIM")
        XCTAssertEqual(item.contentType, .folder)
        XCTAssertEqual(item.itemIdentifier.rawValue, ItemIdentifier.encode(entry.path))
        XCTAssertEqual(item.parentItemIdentifier, .rootContainer)
    }

    func testFileFromEntryHasJPEGContentType() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/sdcard/DCIM/Camera/IMG_001.jpg"),
            name: "IMG_001.jpg",
            kind: .file,
            sizeBytes: 12345,
            modifiedAt: nil,
            isHidden: false
        )
        let item = ProviderItem(entry: entry, parent: RemotePath(raw: "/sdcard/DCIM/Camera"))
        XCTAssertEqual(item.contentType, .jpeg)
        XCTAssertEqual(item.documentSize, NSNumber(value: 12345))
    }
}
