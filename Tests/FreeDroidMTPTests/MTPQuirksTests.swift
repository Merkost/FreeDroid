import Testing
@testable import FreeDroidMTP

@Suite("MTPQuirks")
struct MTPQuirksTests {
    @Test func samsungUsesSmallChunkSize() {
        let quirks = MTPQuirks.for(vendorID: 0x04E8, productID: 0x6860)
        #expect(quirks.maxWriteChunkBytes == 512 * 1024 * 1024)
    }

    @Test func pixelEnablesKeepalive() {
        let quirks = MTPQuirks.for(vendorID: 0x18D1, productID: 0x4EE2)
        #expect(quirks.requiresKeepalive)
    }

    @Test func unknownVendorGetsDefault() {
        let quirks = MTPQuirks.for(vendorID: 0xFFFF, productID: 0xFFFF)
        #expect(quirks.maxWriteChunkBytes == MTPQuirks.default.maxWriteChunkBytes)
        #expect(quirks.requiresKeepalive == false)
    }
}
