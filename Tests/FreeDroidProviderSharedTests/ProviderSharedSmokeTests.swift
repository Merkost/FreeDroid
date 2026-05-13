import XCTest
@testable import FreeDroidProviderShared

final class ProviderSharedSmokeTests: XCTestCase {
    func testReExportsAreReachable() {
        _ = RemotePath.root
        _ = DeviceID(raw: "x")
    }
}
