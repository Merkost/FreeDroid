import SwiftUI

public struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    private let isActive: Bool
    private let content: Content

    public init(isActive: Bool = false, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(isActive ? theme.colors.accentSoft : theme.colors.background1.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(isActive ? theme.colors.accent.opacity(0.25) : theme.colors.line, lineWidth: 1)
                    )
            }
            .shadow(isActive ? Shadows.glow(theme.colors.accent) : ShadowPreset(color: .clear, radius: 0, y: 0))
            .motion(.smooth, value: isActive)
    }
}
