import Testing
import SwiftUI
import SnapshotTesting
@testable import FreeDroidUI

@MainActor
@Suite("Surface snapshots")
struct SurfaceSnapshotTests {
    @Test func materialPanelSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            MaterialPanel {
                Text("Material Panel").font(Typography.title).padding()
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 160), name: "MaterialPanel")
    }

    @Test func cardSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            VStack(spacing: Spacing.md) {
                Card { Text("Idle card").padding(.horizontal) }
                Card(isActive: true) { Text("Active card").padding(.horizontal) }
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 220), name: "Card")
    }

    @Test func sheetSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            Sheet {
                Text("Connect your device").font(Typography.title)
                Text("Tap Allow on your phone to authorize this Mac.").font(Typography.body)
            }
        }
        assertSnapshot(of: view, size: CGSize(width: 520, height: 260), name: "Sheet")
    }
}
