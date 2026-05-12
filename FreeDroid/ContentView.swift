import SwiftUI
import FreeDroidUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @State private var theme: Theme = .dark
    @State private var selectedTab: String = "components"

    var body: some View {
        ZStack {
            AmbientGradientBackground().ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                header
                componentGallery
            }
            .padding(Spacing.xl)
        }
        .frame(width: 720, height: 560)
        .freeDroidTheme(theme)
    }

    private var header: some View {
        HStack {
            Text("FreeDroid Design System").font(Typography.display)
            Spacer()
            PillTabs(selection: $theme, tabs: [("Dark", Theme.dark), ("Light", Theme.light)])
        }
    }

    private var componentGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SectionHeader("Surfaces")
                HStack(spacing: Spacing.md) {
                    Card { Text("Idle card") }
                    Card(isActive: true) { Text("Active card") }
                }
                SectionHeader("Feedback")
                HStack(spacing: Spacing.lg) {
                    LivingRing(color: .green, state: .idle, glyph: "P")
                    LivingRing(color: .blue, state: .transferring, glyph: "G")
                    Spinner()
                }
                SectionHeader("Toasts")
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toast(kind: .success, title: "Pixel 8 Pro mounted")
                    Toast(kind: .warning, title: "OnePlus 12 copying…", detail: "64%")
                }
            }
        }
    }
}
