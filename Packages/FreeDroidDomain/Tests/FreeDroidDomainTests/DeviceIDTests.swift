import Testing
@testable import FreeDroidDomain

@Suite("DeviceID")
struct DeviceIDTests {
    @Test func equalityIsBasedOnRawValue() {
        let first = DeviceID(raw: "ABC123")
        let second = DeviceID(raw: "ABC123")
        let other = DeviceID(raw: "DEF456")
        #expect(first == second)
        #expect(first != other)
    }

    @Test func hashesByRawValue() {
        let set: Set<DeviceID> = [DeviceID(raw: "A"), DeviceID(raw: "A"), DeviceID(raw: "B")]
        #expect(set.count == 2)
    }
}
