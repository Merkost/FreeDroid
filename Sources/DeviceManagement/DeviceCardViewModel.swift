import Foundation
import Observation
import FreeDroidDomain
import FreeDroidUI

@MainActor
@Observable
public final class DeviceCardViewModel: Identifiable {
    public private(set) var device: Device
    public var transferFraction: Double?
    public nonisolated let id: DeviceID

    public init(device: Device) {
        self.device = device
        self.id = device.id
    }

    public func update(device: Device) {
        precondition(device.id == self.id, "DeviceCardViewModel.update called with mismatched id")
        self.device = device
    }
    public var name: String { device.displayName }
    public var glyph: String { String(name.first ?? "•") }

    public var transportKind: IconChipKind {
        switch device.transport {
        case .adb: .adb
        case .mtp: .mtp
        case .wifi: .wifi
        }
    }

    public var transportLabel: String {
        switch device.transport {
        case .adb: "ADB"
        case .mtp: "MTP"
        case .wifi: "WI-FI"
        }
    }

    public var ringState: LivingRingState {
        switch device.connectionState {
        case .ready:
            return transferFraction == nil ? .idle : .transferring
        case .pendingAuthorization:
            return .pendingAuthorization
        case .chargingOnly:
            return .disconnected
        }
    }

    public var statusHint: String? {
        switch device.connectionState {
        case .ready: return nil
        case .pendingAuthorization: return "Tap Allow on your phone"
        case .chargingOnly: return "Set USB to File Transfer, or enable USB Debugging"
        }
    }

    public var isReady: Bool {
        device.connectionState == .ready
    }

    public var hasFinderIntegration: Bool {
        device.connectionState == .ready && device.transport == .adb
    }

    public var finderBadgeText: String? {
        guard isReady else { return nil }
        return device.transport == .adb ? "In Finder" : "In-app only"
    }

    public var capacityDescription: String? {
        guard let capacity = device.storageCapacityBytes else { return nil }
        return ByteCountFormatter().string(fromByteCount: capacity)
    }

    public var subtitle: String? {
        let manufacturer = device.manufacturer.trimmingCharacters(in: .whitespaces)
        let model = device.model.trimmingCharacters(in: .whitespaces)
        if manufacturer.isEmpty && model.isEmpty { return nil }
        if manufacturer.isEmpty { return model }
        if model.isEmpty { return manufacturer }
        return "\(manufacturer) · \(model)"
    }

    public var storageDescription: String? {
        guard let capacity = device.storageCapacityBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .file
        let total = formatter.string(fromByteCount: capacity)
        if let free = device.storageFreeBytes {
            let used = max(0, capacity - free)
            return "\(formatter.string(fromByteCount: used)) of \(total) used"
        }
        return total
    }

    public var storageFraction: Double? {
        guard let capacity = device.storageCapacityBytes, capacity > 0,
              let free = device.storageFreeBytes else { return nil }
        return Double(max(0, capacity - free)) / Double(capacity)
    }

    public func setTransferProgress(_ fraction: Double) {
        transferFraction = max(0, min(1, fraction))
    }

    public func clearTransferProgress() {
        transferFraction = nil
    }
}
