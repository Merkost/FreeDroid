import Testing
@testable import FreeDroidMTP

@Suite("MTPQuirks")
struct MTPQuirksTests {
    @Test func samsungUsesSmallChunkSize() {
        let q = MTPQuirks.for(vendorID: 0x04E8, productID: 0x6860)
        #expect(q.maxWriteChunkBytes == 512 * 1024 * 1024)
    }

    @Test func pixelEnablesKeepalive() {
        let q = MTPQuirks.for(vendorID: 0x18D1, productID: 0x4EE2)
        #expect(q.requiresKeepalive)
    }

    @Test func unknownVendorGetsDefault() {
        let q = MTPQuirks.for(vendorID: 0xFFFF, productID: 0xFFFF)
        #expect(q.maxWriteChunkBytes == MTPQuirks.default.maxWriteChunkBytes)
        #expect(q.requiresKeepalive == false)
    }
}
