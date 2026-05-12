import AppKit
import Foundation
import FreeDroidData
import FreeDroidDomain
import os.log

private let mountLogger = Logger(subsystem: "com.merkost.freedroid", category: "mount")

@MainActor
final class MountCoordinator {
    private let registry: DeviceRegistry
    private let store = MountedVolumeStore()
    private var task: Task<Void, Never>?
    private var inFlight: Set<DeviceID> = []
    private var recentFailures: [DeviceID: Date] = [:]
    private let failureBackoff: TimeInterval = 30

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
        if let lastFailure = recentFailures[device.id], Date().timeIntervalSince(lastFailure) < failureBackoff {
            return
        }
        inFlight.insert(device.id)
        defer { inFlight.remove(device.id) }
        do {
            let mountURL = try await performMount(device)
            await store.record(device.id, mountedAt: mountURL)
            recentFailures.removeValue(forKey: device.id)
            mountLogger.info("Mounted \(device.displayName, privacy: .public) at \(mountURL.path, privacy: .public)")
        } catch {
            recentFailures[device.id] = Date()
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
        let cleanName = device.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let resourceURL = "freedroid://\(device.id.raw)/\(cleanName)"
        let mountPoint = URL(fileURLWithPath: "/Volumes").appendingPathComponent(cleanName, isDirectory: true)
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let result = try await runProcess(
            executable: "/sbin/mount",
            arguments: ["-t", "freedroid", resourceURL, mountPoint.path]
        )

        if result.exitCode != 0 {
            try? FileManager.default.removeItem(at: mountPoint)
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw TransportError.ioFailure(message: "mount -t freedroid \(resourceURL) → exit \(result.exitCode): \(detail)")
        }

        return mountPoint
    }

    private func performUnmount(at mountURL: URL) async throws {
        let result = try await runProcess(
            executable: "/sbin/umount",
            arguments: [mountURL.path]
        )
        if result.exitCode != 0 {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw TransportError.ioFailure(message: "umount \(mountURL.path) → exit \(result.exitCode): \(detail)")
        }
    }

    private struct ProcessOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { finished in
                let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessOutput(exitCode: finished.terminationStatus, stdout: stdout, stderr: stderr))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
