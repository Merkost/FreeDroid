import Testing
@testable import FreeDroidDomain

@Suite("DeviceID")
struct DeviceIDTests {
    @Test func equalityIsBasedOnRawValue() {
        let a = DeviceID(raw: "ABC123")
        let b = DeviceID(raw: "ABC123")
        let c = DeviceID(raw: "DEF456")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func hashesByRawValue() {
        let set: Set<DeviceID> = [DeviceID(raw: "A"), DeviceID(raw: "A"), DeviceID(raw: "B")]
        #expect(set.count == 2)
    }
}
