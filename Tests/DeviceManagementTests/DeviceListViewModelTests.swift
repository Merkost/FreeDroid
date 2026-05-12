import Foundation
import Testing
import FreeDroidDomain
@testable import DeviceManagement

@MainActor
@Suite("DeviceListViewModel")
struct DeviceListViewModelTests {
    private func device(_ name: String, transport: TransportKind = .adb) -> Device {
        Device(
            id: DeviceID(raw: name),
            displayName: name,
            manufacturer: "Test",
            model: name,
            storageCapacityBytes: nil,
            storageFreeBytes: nil,
            transport: transport
        )
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
        repo.emit([device("A")])
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.devices.count == 1)
        #expect(vm.selectedID == DeviceID(raw: "A"))
        observeTask.cancel()
    }

    @Test func preservesSelectionAcrossUpdates() async throws {
        let repo = StubDeviceRepository(initial: [device("A"), device("B")])
        let vm = DeviceListViewModel(repository: repo)
        let observeTask = Task { await vm.observe() }
        try await Task.sleep(for: .milliseconds(50))
        vm.select(DeviceID(raw: "B"))
        repo.emit([device("B"), device("C")])
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.selectedID == DeviceID(raw: "B"))
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
