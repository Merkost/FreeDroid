import Foundation
import Observation
import FreeDroidDomain
import FreeDroidUI

@MainActor
@Observable
public final class DeviceCardViewModel: Identifiable {
    public let device: Device
    public var transferFraction: Double?

    public init(device: Device) {
        self.device = device
    }

    public nonisolated var id: DeviceID { device.id }
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
        case .chargingOnly: return "Switch USB mode to File Transfer"
        }
    }

    public var isReady: Bool {
        device.connectionState == .ready
    }

    public var capacityDescription: String? {
        guard let capacity = device.storageCapacityBytes else { return nil }
        return ByteCountFormatter().string(fromByteCount: capacity)
    }

    public func setTransferProgress(_ fraction: Double) {
        transferFraction = max(0, min(1, fraction))
    }

    public func clearTransferProgress() {
        transferFraction = nil
    }
}
