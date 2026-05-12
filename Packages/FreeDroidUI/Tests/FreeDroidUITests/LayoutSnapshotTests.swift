import Testing
import SwiftUI
@testable import FreeDroidUI

@MainActor
@Suite("Layout snapshots")
struct LayoutSnapshotTests {
    @Test func masonrySnapshot() {
        let palettes: [(Color, CGFloat)] = [
            (.blue, 140), (.purple, 110), (.green, 180), (.orange, 125),
            (.red, 150), (.cyan, 95), (.yellow, 160), (.pink, 130)
        ]
        let view = ZStack {
            AmbientGradientBackground()
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("Today", detail: "42 photos")
                MasonryLayout(columns: 4, spacing: Spacing.md - 2) {
                    ForEach(0..<palettes.count, id: \.self) { idx in
                        let (color, height) = palettes[idx]
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(color.opacity(0.4))
                            .frame(height: height)
                    }
                }
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 600, height: 400), name: "Masonry")
    }
}
