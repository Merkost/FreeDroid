import Foundation
import Observation
import SwiftUI
import FreeDroidUI

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum ParallelTransfers: Int, CaseIterable, Identifiable, Sendable {
    case one = 1
    case three = 3
    case five = 5
    case eight = 8

    public var id: Int { rawValue }
    public var label: String { "\(rawValue)" }
}

@MainActor
@Observable
public final class AppPreferences {
    public var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    public var parallelTransfers: ParallelTransfers {
        didSet {
            UserDefaults.standard.set(parallelTransfers.rawValue, forKey: Self.parallelTransfersKey)
        }
    }

    public var useWireProtocol: Bool {
        didSet {
            Self.sharedSuite.set(useWireProtocol, forKey: Self.wireProtocolKey)
        }
    }

    private static let appearanceKey = "FreeDroid.Appearance"
    private static let parallelTransfersKey = "FreeDroid.ParallelTransfersPerDevice"
    private static let wireProtocolKey = "freedroid.useWireClient"
    private static let wireEnableMigrationKey = "FreeDroid.WireClientEnable.v2"
    private static let sharedSuite = UserDefaults(suiteName: "group.com.merkost.freedroid") ?? .standard

    public init() {
        let stored = UserDefaults.standard.string(forKey: Self.appearanceKey)
            ?? AppearanceMode.system.rawValue
        self.appearance = AppearanceMode(rawValue: stored) ?? .system
        let parallelStored = UserDefaults.standard.integer(forKey: Self.parallelTransfersKey)
        self.parallelTransfers = ParallelTransfers(rawValue: parallelStored) ?? .three
        if !Self.sharedSuite.bool(forKey: Self.wireEnableMigrationKey) {
            Self.sharedSuite.set(true, forKey: Self.wireProtocolKey)
            Self.sharedSuite.set(true, forKey: Self.wireEnableMigrationKey)
        }
        self.useWireProtocol = Self.sharedSuite.bool(forKey: Self.wireProtocolKey)
    }

    public func theme(for systemColorScheme: ColorScheme) -> Theme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return Theme.from(systemColorScheme)
        }
    }
}
