import SwiftUI

public struct ShadowPreset: Sendable, Equatable {
    public let color: Color
    public let radius: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.y = y
    }
}

public enum Shadows {
    /// For floating chips, pills, and toasts — intentionally small.
    public static let subtle = ShadowPreset(color: .black.opacity(0.18), radius: 8, y: 4)

    /// For cards on dark surfaces — medium lift.
    public static let elevated = ShadowPreset(color: .black.opacity(0.28), radius: 16, y: 8)

    /// For command bars and floating panels — large.
    public static let floating = ShadowPreset(color: .black.opacity(0.38), radius: 28, y: 14)

    /// For sheets and modals — heavy xl drop shadow.
    public static let dramatic = ShadowPreset(color: .black.opacity(0.45), radius: 48, y: 24)

    /// Colored glow for active / selected states (e.g. accent halo around active Card).
    public static func glow(_ color: Color, intensity: Double = 0.28) -> ShadowPreset {
        ShadowPreset(color: color.opacity(intensity), radius: 24, y: 10)
    }
}

public extension View {
    func shadow(_ preset: ShadowPreset) -> some View {
        shadow(color: preset.color, radius: preset.radius, x: 0, y: preset.y)
    }
}
