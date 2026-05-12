import SwiftUI

public struct MaterialPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = Radius.lg, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(theme.colors.line, lineWidth: 1)
                    )
            }
    }
}
