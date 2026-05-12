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

@MainActor
@Observable
public final class AppPreferences {
    public var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    private static let appearanceKey = "FreeDroid.Appearance"

    public init() {
        let stored = UserDefaults.standard.string(forKey: Self.appearanceKey)
            ?? AppearanceMode.system.rawValue
        self.appearance = AppearanceMode(rawValue: stored) ?? .system
    }

    public func theme(for systemColorScheme: ColorScheme) -> Theme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return Theme.from(systemColorScheme)
        }
    }
}
