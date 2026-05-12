import SwiftUI

public struct Sheet<Content: View>: View {
    @Environment(\.theme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            content
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 480)
        .background {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(theme.colors.lineStrong, lineWidth: 1)
                )
        }
        .shadow(Shadows.dramatic)
    }
}
