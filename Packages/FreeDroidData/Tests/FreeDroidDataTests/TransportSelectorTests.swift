import Foundation
import Testing
import FreeDroidDomain
@testable import FreeDroidData

@Suite("TransportSelector")
struct TransportSelectorTests {
    @Test func prefersADBWhenAuthorized() {
        let result = TransportSelector.select(
            adbAvailable: true,
            adbAuthorized: true,
            mtpAvailable: true,
            pinned: nil
        )
        #expect(result == .adb)
    }

    @Test func fallsBackToMTPWhenADBUnauthorized() {
        let result = TransportSelector.select(
            adbAvailable: true,
            adbAuthorized: false,
            mtpAvailable: true,
            pinned: nil
        )
        #expect(result == .mtp)
    }

    @Test func usesMTPWhenADBMissing() {
        let result = TransportSelector.select(
            adbAvailable: false,
            adbAuthorized: false,
            mtpAvailable: true,
            pinned: nil
        )
        #expect(result == .mtp)
    }

    @Test func returnsNilWhenNothingAvailable() {
        let result = TransportSelector.select(
            adbAvailable: false,
            adbAuthorized: false,
            mtpAvailable: false,
            pinned: nil
        )
        #expect(result == nil)
    }

    @Test func userPinHonored() {
        let result = TransportSelector.select(
            adbAvailable: true,
            adbAuthorized: true,
            mtpAvailable: true,
            pinned: .mtp
        )
        #expect(result == .mtp)
    }
}
