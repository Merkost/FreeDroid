import XCTest
@testable import FreeDroidProviderShared

final class ItemIdentifierTests: XCTestCase {
    func testRootIsAppleRootContainerConstant() {
        XCTAssertEqual(ItemIdentifier.encode(.root), "NSFileProviderRootContainerItemIdentifier")
    }

    func testEncodeDecodeRoundTrip() {
        let path = RemotePath(raw: "/sdcard/DCIM/Camera/IMG_001.jpg")
        let encoded = ItemIdentifier.encode(path)
        XCTAssertTrue(encoded.hasPrefix("p:"))
        XCTAssertEqual(ItemIdentifier.decode(encoded), path)
    }

    func testDecodeAppleRootReturnsRoot() {
        XCTAssertEqual(ItemIdentifier.decode("NSFileProviderRootContainerItemIdentifier"), .root)
    }

    func testDecodeRejectsUnknownPrefix() {
        XCTAssertNil(ItemIdentifier.decode("junk:abc"))
    }

    func testDecodeRejectsMalformedBase64() {
        XCTAssertNil(ItemIdentifier.decode("p:not-base-64!!!"))
    }

    func testPathsWithSpacesAndUnicode() {
        let path = RemotePath(raw: "/sdcard/Pictures/Mon Été 🌞/photo.jpg")
        let roundTripped = ItemIdentifier.decode(ItemIdentifier.encode(path))
        XCTAssertEqual(roundTripped, path)
    }
}
