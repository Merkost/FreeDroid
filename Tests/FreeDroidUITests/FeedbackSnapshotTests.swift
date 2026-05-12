import Testing
import SwiftUI
@testable import FreeDroidUI

@MainActor
@Suite("Feedback snapshots")
struct FeedbackSnapshotTests {
    @Test func fluidProgressSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            Card {
                ZStack {
                    HStack(spacing: Spacing.md) {
                        Circle()
                            .strokeBorder(.green.opacity(0.8), lineWidth: 2)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading) {
                            Text("OnePlus 12").font(Typography.bodyEmphasized)
                            Text("Copying · 1.4 / 2.2 GB").font(Typography.caption)
                        }
                        Spacer()
                    }
                    FluidProgress(fraction: 0.64)
                }
                .frame(width: 240)
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 120), name: "FluidProgressCard")
    }

    @Test func toastSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            VStack(spacing: Spacing.sm) {
                Toast(kind: .success, title: "Pixel 8 Pro mounted")
                Toast(kind: .warning, title: "OnePlus 12 copying…", detail: "64%")
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 160), name: "Toasts")
    }
}
