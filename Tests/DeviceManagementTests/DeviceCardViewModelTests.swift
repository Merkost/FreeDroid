import Foundation
import Testing
import FreeDroidDomain
import FreeDroidUI
@testable import DeviceManagement

@MainActor
@Suite("DeviceCardViewModel")
struct DeviceCardViewModelTests {
    private func device(
        _ identifier: String,
        transport: TransportKind,
        connectionState: DeviceConnectionState = .ready
    ) -> Device {
        Device(
            id: DeviceID(raw: identifier),
            displayName: identifier,
            manufacturer: "T",
            model: identifier,
            storageCapacityBytes: nil,
            storageFreeBytes: nil,
            transport: transport,
            connectionState: connectionState
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

    @Test func statusHintNilForReadyDevice() {
        let vm = DeviceCardViewModel(device: device("Pixel", transport: .adb, connectionState: .ready))
        #expect(vm.statusHint == nil)
    }

    @Test func statusHintForPendingAuthorization() {
        let vm = DeviceCardViewModel(
            device: device("Galaxy", transport: .adb, connectionState: .pendingAuthorization)
        )
        #expect(vm.statusHint == "Tap Allow on your phone")
    }

    @Test func statusHintForChargingOnly() {
        let vm = DeviceCardViewModel(
            device: device("Pixel", transport: .adb, connectionState: .chargingOnly)
        )
        #expect(vm.statusHint == "Switch USB mode to File Transfer")
    }

    @Test func ringStateDisconnectedForPendingAuthorization() {
        let vm = DeviceCardViewModel(
            device: device("Galaxy", transport: .adb, connectionState: .pendingAuthorization)
        )
        #expect(vm.ringState == .disconnected)
    }

    @Test func ringStateDisconnectedForChargingOnly() {
        let vm = DeviceCardViewModel(
            device: device("Pixel", transport: .adb, connectionState: .chargingOnly)
        )
        #expect(vm.ringState == .disconnected)
    }

    @Test func isReadyOnlyForReadyState() {
        let readyVM = DeviceCardViewModel(device: device("A", transport: .adb, connectionState: .ready))
        let pendingVM = DeviceCardViewModel(
            device: device("B", transport: .adb, connectionState: .pendingAuthorization)
        )
        let chargingVM = DeviceCardViewModel(
            device: device("C", transport: .adb, connectionState: .chargingOnly)
        )
        #expect(readyVM.isReady)
        #expect(!pendingVM.isReady)
        #expect(!chargingVM.isReady)
    }
}
