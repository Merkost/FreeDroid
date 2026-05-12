import SwiftUI

struct AmbientGradientBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let radius = max(size.width, size.height) * 0.6
            context.fill(
                Path(ellipseIn: CGRect(
                    x: size.width * 0.2 - radius / 2,
                    y: size.height * 0.3 - radius / 2,
                    width: radius,
                    height: radius
                )),
                with: .color(theme.colors.accent.opacity(0.10))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: size.width * 0.85 - radius / 2,
                    y: size.height * 0.75 - radius / 2,
                    width: radius,
                    height: radius
                )),
                with: .color(theme.colors.mtp.opacity(0.08))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: size.width * 0.5 - radius / 2,
                    y: size.height * 1.0 - radius / 2,
                    width: radius,
                    height: radius
                )),
                with: .color(theme.colors.wifi.opacity(0.06))
            )
        }
        .blur(radius: 80)
        .background(theme.colors.background0)
    }
}
