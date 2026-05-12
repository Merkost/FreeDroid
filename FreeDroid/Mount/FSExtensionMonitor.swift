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
        status = detectStatus()
    }

    private func detectStatus() -> FSExtensionStatus {
        let extensionsURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("FreeDroidFS.appex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: extensionsURL.path) else {
            return .notLoaded
        }
        return .loaded
    }
}
