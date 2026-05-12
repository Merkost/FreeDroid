import Foundation
import Testing
import FreeDroidDomain
import FreeDroidUI
@testable import DeviceManagement

@MainActor
@Suite("DeviceCardViewModel")
struct DeviceCardViewModelTests {
    private func device(_ identifier: String, transport: TransportKind) -> Device {
        Device(
            id: DeviceID(raw: identifier),
            displayName: identifier,
            manufacturer: "T",
            model: identifier,
            storageCapacityBytes: nil,
            storageFreeBytes: nil,
            transport: transport
        )
    }

    @Test func glyphIsFirstLetter() {
        let vm = DeviceCardViewModel(device: device("Pixel", transport: .adb))
        #expect(vm.glyph == "P")
    }

    @Test func subtitleHasTransportBadge() {
        let vm = DeviceCardViewModel(device: device("Galaxy", transport: .mtp))
        #expect(vm.transportLabel == "MTP")
        #expect(vm.transportKind == .mtp)
    }

    @Test func ringStateIdleByDefault() {
        let vm = DeviceCardViewModel(device: device("X", transport: .adb))
        #expect(vm.ringState == .idle)
    }

    @Test func ringStateTransferringWhenActive() {
        let vm = DeviceCardViewModel(device: device("X", transport: .adb))
        vm.setTransferProgress(0.3)
        #expect(vm.ringState == .transferring)
        vm.clearTransferProgress()
        #expect(vm.ringState == .idle)
    }
}
