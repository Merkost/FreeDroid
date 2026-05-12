import AppKit
import Foundation
import FreeDroidData
import FreeDroidDomain
import NetFS
import os.log

private let mountLogger = Logger(subsystem: "com.merkost.freedroid", category: "mount")

// MARK: - MountCoordinator

/// Observes the DeviceRegistry and mounts/unmounts each ready Android device as a
/// Finder volume under /Volumes/<DeviceName>.
///
/// Mount strategy: NetFSMountURLSync (available since macOS 10.8, no root required).
/// The call passes a freedroid://<serial>/<displayName> URL to the NetFS layer, which
/// forwards it to fskitd; fskitd looks up the registered FSKit extension whose
/// FSSupportedSchemes contains "freedroid" and invokes probeResource then loadResource
/// with an FSGenericURLResource wrapping that URL.
///
/// Unmount strategy: NSWorkspace.shared.unmountAndEjectDeviceAtURL (no root required).
@MainActor
final class MountCoordinator {
    private let registry: DeviceRegistry
    private let store = MountedVolumeStore()
    private var task: Task<Void, Never>?
    private var inFlight: Set<DeviceID> = []

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
    }

    private func reconcile(_ devices: [Device]) async {
        let readyIDs = Set(devices.filter { $0.connectionState == .ready }.map(\.id))
        for device in devices where device.connectionState == .ready {
            await mountIfNeeded(device)
        }
        let recorded = await store.all()
        for (deviceID, mountURL) in recorded where !readyIDs.contains(deviceID) {
            await unmount(deviceID: deviceID, at: mountURL)
        }
    }

    private func mountIfNeeded(_ device: Device) async {
        guard !inFlight.contains(device.id) else { return }
        let alreadyMounted = await store.mountURL(for: device.id) != nil
        guard !alreadyMounted else { return }
        inFlight.insert(device.id)
        defer { inFlight.remove(device.id) }
        do {
            let mountURL = try await performMount(device)
            await store.record(device.id, mountedAt: mountURL)
            mountLogger.info("Mounted \(device.displayName, privacy: .public) at \(mountURL.path, privacy: .public)")
        } catch {
            mountLogger.error("Mount failed for \(device.displayName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func unmount(deviceID: DeviceID, at mountURL: URL) async {
        do {
            try await performUnmount(at: mountURL)
            await store.forget(deviceID)
            mountLogger.info("Unmounted \(mountURL.path, privacy: .public)")
        } catch {
            mountLogger.error("Unmount failed at \(mountURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func performMount(_ device: Device) async throws -> URL {
        var components = URLComponents()
        components.scheme = "freedroid"
        components.host = device.id.raw
        let safeName = device.displayName
            .replacingOccurrences(of: "/", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "Android"
        components.path = "/" + safeName
        guard let resourceURL = components.url else {
            throw TransportError.unsupported(reason: "Cannot construct freedroid:// URL for device \(device.id.raw)")
        }

        let mountDir = URL(fileURLWithPath: "/Volumes")
        let cleanName = device.displayName.replacingOccurrences(of: "/", with: "-")
        let requestedMount = mountDir.appendingPathComponent(cleanName, isDirectory: true)
        try? FileManager.default.createDirectory(at: requestedMount, withIntermediateDirectories: true)

        let openOptions = NSMutableDictionary()
        openOptions[kNetFSUseGuestKey] = true as CFBoolean

        let mountOptions = NSMutableDictionary()
        mountOptions[kNetFSMountAtMountDirKey] = true as CFBoolean

        var mountpoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            resourceURL as CFURL,
            requestedMount as CFURL,
            nil,
            nil,
            openOptions as CFMutableDictionary,
            mountOptions as CFMutableDictionary,
            &mountpoints
        )

        let resolvedPaths = mountpoints?.takeRetainedValue() as? [String]

        if status != 0 {
            try? FileManager.default.removeItem(at: requestedMount)
            throw TransportError.ioFailure(message: "NetFSMountURLSync returned \(status) for \(resourceURL.absoluteString)")
        }

        if let first = resolvedPaths?.first {
            return URL(fileURLWithPath: first, isDirectory: true)
        }
        return requestedMount
    }

    private func performUnmount(at mountURL: URL) async throws {
        try await NSWorkspace.shared.unmountAndEjectDevice(at: mountURL)
    }
}
