import Foundation
import Testing
import FreeDroidDomain
@testable import DeviceManagement

@MainActor
@Suite("DeviceListViewModel")
struct DeviceListViewModelTests {
    private func device(
        _ name: String,
        transport: TransportKind = .adb,
        connectionState: DeviceConnectionState = .ready
    ) -> Device {
        Device(
            id: DeviceID(raw: name),
            displayName: name,
            manufacturer: "Test",
            model: name,
            storageCapacityBytes: nil,
            storageFreeBytes: nil,
            transport: transport,
            connectionState: connectionState
        )
    }

    private func drain() async throws {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func emptyAtFirst() {
        let vm = DeviceListViewModel(repository: StubDeviceRepository(initial: []))
        #expect(vm.devices.isEmpty)
        #expect(vm.selectedID == nil)
    }

    @Test func selectsFirstWhenDevicesAppear() async throws {
        let repo = StubDeviceRepository(initial: [])
        let vm = DeviceListViewModel(repository: repo)
        let observeTask = Task { await vm.observe() }
        await Task.yield()
        repo.emit([device("A")])
        try await drain()
        #expect(vm.devices.count == 1)
        #expect(vm.selectedID == DeviceID(raw: "A"))
        observeTask.cancel()
    }

    @Test func preservesSelectionAcrossUpdates() async throws {
        let repo = StubDeviceRepository(initial: [device("A"), device("B")])
        let vm = DeviceListViewModel(repository: repo)
        let observeTask = Task { await vm.observe() }
        try await drain()
        vm.select(DeviceID(raw: "B"))
        repo.emit([device("B"), device("C")])
        try await drain()
        #expect(vm.selectedID == DeviceID(raw: "B"))
        observeTask.cancel()
    }

    @Test func doesNotAutoSelectNonReadyDevices() async throws {
        let repo = StubDeviceRepository(initial: [])
        let vm = DeviceListViewModel(repository: repo)
        let observeTask = Task { await vm.observe() }
        await Task.yield()
        repo.emit([
            device("X", connectionState: .chargingOnly),
            device("Y", connectionState: .pendingAuthorization)
        ])
        try await drain()
        #expect(vm.selectedID == nil)
        observeTask.cancel()
    }

    @Test func autoSelectsFirstReadyDeviceSkippingNonReady() async throws {
        let repo = StubDeviceRepository(initial: [])
        let vm = DeviceListViewModel(repository: repo)
        let observeTask = Task { await vm.observe() }
        await Task.yield()
        repo.emit([
            device("X", connectionState: .chargingOnly),
            device("ReadyDevice", connectionState: .ready)
        ])
        try await drain()
        #expect(vm.selectedID == DeviceID(raw: "ReadyDevice"))
        observeTask.cancel()
    }
}

final class StubDeviceRepository: DeviceRepository, @unchecked Sendable {
    private let continuation: AsyncStream<[Device]>.Continuation
    private let stream: AsyncStream<[Device]>
    private var devices: [Device]

    init(initial: [Device]) {
        var cont: AsyncStream<[Device]>.Continuation!
        self.stream = AsyncStream { cont = $0 }
        self.continuation = cont
        self.devices = initial
        cont.yield(initial)
    }

    func observe() -> AsyncStream<[Device]> { stream }
    func device(_ identifier: DeviceID) async -> Device? { devices.first { $0.id == identifier } }

    func emit(_ snapshot: [Device]) {
        devices = snapshot
        continuation.yield(snapshot)
    }
}
