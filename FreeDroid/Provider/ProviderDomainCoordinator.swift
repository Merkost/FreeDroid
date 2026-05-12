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
            await self.removeAllDomains()
            for await snapshot in await self.registry.observe() {
                await self.reconcile(snapshot)
            }
        }
    }

    private func removeAllDomains() async {
        do {
            let existing = try await Self.fetchDomains()
            let ours = existing.filter { ourIdentifierLooksLikeAndroid($0.identifier.rawValue) }
            for domain in ours {
                try? await NSFileProviderManager.remove(domain)
                providerLogger.info("Removed domain to force cache flush: \(domain.displayName, privacy: .public)")
            }
        } catch {
            providerLogger.error("List domains failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func ourIdentifierLooksLikeAndroid(_ raw: String) -> Bool {
        if raw.hasPrefix("USB-") { return true }
        if raw.contains(":") { return true }
        if raw.hasPrefix("emulator-") { return true }
        if raw.count == 16, raw.allSatisfy({ $0.isHexDigit }) { return true }
        if raw.range(of: "^[A-Z0-9]{8,}$", options: .regularExpression) != nil { return true }
        return false
    }

    private static func fetchDomains() async throws -> [NSFileProviderDomain] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[NSFileProviderDomain], Error>) in
            NSFileProviderManager.getDomainsWithCompletionHandler { (domains: [NSFileProviderDomain], error: Error?) in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    nonisolated(unsafe) let result = domains
                    continuation.resume(returning: result)
                }
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
            providerLogger.info("Registered domain for \(device.displayName, privacy: .public)")
        } catch {
            providerLogger.info("Domain already registered (or add failed): \(device.displayName, privacy: .public) — \(String(describing: error), privacy: .public)")
        }
        active.insert(device.id)
        signalRefresh(for: domain)
    }

    private func signalRefresh(for domain: NSFileProviderDomain) {
        guard let manager = NSFileProviderManager(for: domain) else { return }
        manager.signalEnumerator(for: .workingSet) { _ in }
        manager.signalEnumerator(for: .rootContainer) { _ in }
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
