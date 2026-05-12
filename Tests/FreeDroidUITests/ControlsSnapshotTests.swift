import Testing
import SwiftUI
@testable import FreeDroidUI

@MainActor
@Suite("Controls snapshots")
struct ControlsSnapshotTests {
    @Test func iconChipsSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            HStack(spacing: Spacing.sm) {
                IconChip("ADB", kind: .adb)
                IconChip("MTP", kind: .mtp)
                IconChip("Wi-Fi", kind: .wifi)
                IconChip("Off", kind: .off)
            }
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 360, height: 80), name: "IconChips")
    }

    @Test func pillTabsSnapshot() {
        let binding = Binding<String>.constant("gallery")
        let view = ZStack {
            AmbientGradientBackground()
            PillTabs(selection: binding, tabs: [
                ("Gallery", "gallery"),
                ("Files", "files"),
                ("Apps", "apps")
            ])
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 320, height: 80), name: "PillTabs")
    }

    @Test func commandStripSnapshot() {
        let view = ZStack {
            AmbientGradientBackground()
            CommandStrip(selectionCount: 3, actions: [
                CommandStripAction(label: "Copy to Mac", systemImage: "arrow.down.circle", hotkey: "⌘D") { },
                CommandStripAction(label: "Delete", systemImage: "trash") { },
                CommandStripAction(label: "Reveal in Finder", systemImage: "folder", hotkey: "⏎", isPrimary: true) { }
            ])
            .padding()
        }
        assertSnapshot(of: view, size: CGSize(width: 720, height: 100), name: "CommandStrip")
    }
}
