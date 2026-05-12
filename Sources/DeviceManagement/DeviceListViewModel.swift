import Foundation
import Observation
import FreeDroidDomain

@MainActor
@Observable
public final class DeviceListViewModel {
    public private(set) var devices: [Device] = []
    public var selectedID: DeviceID?
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
        guard devices.contains(where: { $0.id == identifier && $0.connectionState == .ready }) else { return }
        selectedID = identifier
    }

    private func apply(_ snapshot: [Device]) {
        devices = snapshot
        if let current = selectedID, devices.contains(where: { $0.id == current }) {
            return
        }
        selectedID = snapshot.first(where: { $0.connectionState == .ready })?.id
    }
}
