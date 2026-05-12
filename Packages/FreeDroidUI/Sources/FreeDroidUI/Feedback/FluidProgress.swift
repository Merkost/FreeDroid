import SwiftUI

public struct FluidProgress: View {
    @Environment(\.theme) private var theme
    private let fraction: Double
    private let cornerRadius: CGFloat

    public init(fraction: Double, cornerRadius: CGFloat = Radius.lg) {
        self.fraction = max(0, min(1, fraction))
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        GeometryReader { geo in
            let fillHeight = geo.size.height * fraction
            ZStack(alignment: .bottom) {
                Color.clear
                LinearGradient(
                    colors: [theme.colors.accent.opacity(0.10), theme.colors.accent.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fillHeight)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.colors.accent.opacity(0.5))
                        .frame(height: 1)
                        .blur(radius: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .motion(.smooth, value: fraction)
        }
        .allowsHitTesting(false)
    }
}
