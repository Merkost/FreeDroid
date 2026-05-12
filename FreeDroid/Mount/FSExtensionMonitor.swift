import Foundation
import FSKit
import Observation
import os.log

/// The registration and load state of the FreeDroidFS file-system extension.
public enum FSExtensionStatus: Sendable, Equatable {
    case unknown
    case loaded
    case notLoaded
}

/// Periodically queries FSKit for the presence of the FreeDroidFS extension
/// and publishes the current ``FSExtensionStatus``.
@available(macOS 15.4, *)
@MainActor
@Observable
public final class FSExtensionMonitor {
    public private(set) var status: FSExtensionStatus = .unknown

    private let bundleIdentifier: String
    private let logger = Logger(subsystem: "com.merkost.freedroid", category: "extension-monitor")
    private var pollingTask: Task<Void, Never>?

    public init(bundleIdentifier: String = "com.merkost.freedroid.FreeDroidFS") {
        self.bundleIdentifier = bundleIdentifier
    }

    public func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func refresh() async {
        let identifier = bundleIdentifier
        let log = logger
        let result: FSExtensionStatus = await withCheckedContinuation { continuation in
            FSClient.shared.fetchInstalledExtensions { modules, error in
                if let error {
                    log.error("fetchInstalledExtensions failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: .unknown)
                    return
                }
                let identifiers = modules?.map(\.bundleIdentifier) ?? []
                let isLoaded = identifiers.contains(identifier)
                continuation.resume(returning: isLoaded ? .loaded : .notLoaded)
            }
        }
        status = result
    }
}
