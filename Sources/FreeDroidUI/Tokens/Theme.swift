import SwiftUI

public struct Theme: Sendable, Equatable, Hashable {
    public let colorScheme: ColorScheme
    public let colors: ColorTokens

    public static let dark = Theme(colorScheme: .dark, colors: .dark)
    public static let light = Theme(colorScheme: .light, colors: .light)

    public static func from(_ scheme: ColorScheme) -> Theme {
        scheme == .light ? .light : .dark
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(colorScheme == .dark ? 0 : 1)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .dark
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

public extension View {
    func freeDroidTheme(_ theme: Theme) -> some View {
        self
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
    }
}
