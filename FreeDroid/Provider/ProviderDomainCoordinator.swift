import FileProvider
import Foundation
import FreeDroidData
import FreeDroidDomain
import os.log

private let providerLogger = Logger(subsystem: "com.merkost.freedroid", category: "provider")

@MainActor
final class ProviderDomainCoordinator {
    private let registry: DeviceRegistry
    private var task: Task<Void, Never>?
    private var active: Set<DeviceID> = []

    init(registry: DeviceRegistry) {
        self.registry = registry
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            for await snapshot in await self.registry.observe() {
                await self.reconcile(snapshot)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        Task { await self.removeAll() }
    }

    private func reconcile(_ devices: [Device]) async {
        let supported = devices.filter { $0.connectionState == .ready && $0.transport == .adb }
        let readyIDs = Set(supported.map(\.id))
        for device in supported {
            await addIfNeeded(device)
        }
        for id in active.subtracting(readyIDs) {
            await removeDomain(for: id)
        }
    }

    private func addIfNeeded(_ device: Device) async {
        guard !active.contains(device.id) else { return }
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(device.id.raw),
            displayName: device.displayName
        )
        do {
            try await NSFileProviderManager.add(domain)
            active.insert(device.id)
            providerLogger.info("Registered domain for \(device.displayName, privacy: .public)")
        } catch {
            providerLogger.error("add(\(device.displayName, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

    private func removeDomain(for deviceID: DeviceID) async {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(deviceID.raw),
            displayName: ""
        )
        do {
            try await NSFileProviderManager.remove(domain)
            active.remove(deviceID)
            providerLogger.info("Removed domain \(deviceID.raw, privacy: .public)")
        } catch {
            providerLogger.error("remove(\(deviceID.raw, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

    private func removeAll() async {
        for id in active { await removeDomain(for: id) }
    }
}
