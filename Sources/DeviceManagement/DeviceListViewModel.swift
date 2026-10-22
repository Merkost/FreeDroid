import Foundation
import Observation
import FreeDroidDomain

@MainActor
@Observable
public final class DeviceListViewModel {
    public private(set) var devices: [Device] = []
    public var selectedID: DeviceID?
    public private(set) var selectedIDs: Set<DeviceID> = []
    private let repository: any DeviceRepository

    public init(repository: any DeviceRepository) {
        self.repository = repository
    }

    public func observe() async {
        for await snapshot in repository.observe() {
            apply(snapshot)
        }
    }

    public func select(_ identifier: DeviceID) {
        select(identifier, additive: false)
    }

    public func select(_ identifier: DeviceID, additive: Bool) {
        guard devices.contains(where: { $0.id == identifier && $0.connectionState == .ready }) else { return }
        selectedID = identifier
        if additive {
            if selectedIDs.contains(identifier) { selectedIDs.remove(identifier) }
            else { selectedIDs.insert(identifier) }
        } else {
            selectedIDs = [identifier]
        }
    }

    private func apply(_ snapshot: [Device]) {
        devices = snapshot
        if let current = selectedID, devices.contains(where: { $0.id == current }) {
            return
        }
        selectedID = snapshot.first(where: { $0.connectionState == .ready })?.id
        selectedIDs = Set(selectedIDs.filter { id in snapshot.contains { $0.id == id && $0.connectionState == .ready } })
        if selectedIDs.isEmpty, let selectedID { selectedIDs = [selectedID] }
    }
}
