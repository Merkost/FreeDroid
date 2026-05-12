import XCTest
import FileProvider
@testable import FreeDroidProviderShared

final class ProviderErrorMappingTests: XCTestCase {
    func testNotConnectedMapsToServerUnreachable() {
        let mapped = ProviderError.map(TransportError.notConnected)
        XCTAssertEqual((mapped as NSError).domain, NSFileProviderErrorDomain)
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.serverUnreachable.rawValue)
    }

    func testNotFoundMapsToNoSuchItem() {
        let mapped = ProviderError.map(TransportError.notFound(RemotePath(raw: "/x")))
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.noSuchItem.rawValue)
    }

    func testAlreadyExistsMapsToFilenameCollision() {
        let mapped = ProviderError.map(TransportError.alreadyExists(RemotePath(raw: "/x")))
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.filenameCollision.rawValue)
    }

    func testIOFailureMapsToCannotSynchronize() {
        let mapped = ProviderError.map(TransportError.ioFailure(message: "boom"))
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.cannotSynchronize.rawValue)
    }
}
