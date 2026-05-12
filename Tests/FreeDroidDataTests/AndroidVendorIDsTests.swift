import Foundation
import Testing
@testable import FreeDroidData

@Suite("AndroidVendorIDs")
struct AndroidVendorIDsTests {
    @Test func recognizesGoogle() {
        #expect(AndroidVendorIDs.isAndroidVendor(0x18D1))
    }

    @Test func recognizesSamsung() {
        #expect(AndroidVendorIDs.isAndroidVendor(0x04E8))
    }

    @Test func rejectsUnknownVendor() {
        #expect(!AndroidVendorIDs.isAndroidVendor(0xFFFF))
        #expect(!AndroidVendorIDs.isAndroidVendor(0x0000))
        #expect(!AndroidVendorIDs.isAndroidVendor(0x1234))
    }

    @Test func vendorNameForGoogle() {
        #expect(AndroidVendorIDs.vendorName(for: 0x18D1) == "Google")
    }

    @Test func vendorNameForSamsung() {
        #expect(AndroidVendorIDs.vendorName(for: 0x04E8) == "Samsung")
    }

    @Test func vendorNameForUnknownIsNil() {
        #expect(AndroidVendorIDs.vendorName(for: 0xFFFF) == nil)
    }

    @Test func allKnownVendorsRecognized() {
        for vendorID in AndroidVendorIDs.knownVendors {
            #expect(AndroidVendorIDs.isAndroidVendor(vendorID))
        }
    }
}
