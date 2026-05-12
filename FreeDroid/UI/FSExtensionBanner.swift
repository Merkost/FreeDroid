import SwiftUI
import FreeDroidUI

struct FSExtensionBanner: View {
    @Environment(\.theme) private var theme
    var status: FSExtensionStatus
    var onOpenSettings: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        if status == .notLoaded {
            HStack(spacing: Spacing.md) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.colors.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finder integration not enabled")
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(theme.colors.text0)
                    Text("Enable \u{201C}FreeDroid\u{201D} in Login Items & Extensions to mount Android devices in Finder.")
                        .font(Typography.caption)
                        .foregroundStyle(theme.colors.text2)
                }
                Spacer()
                Button("Refresh") { onRefresh() }
                    .buttonStyle(.bordered)
                Button("Open Settings\u{2026}") { onOpenSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.colors.accent)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(theme.colors.warning.opacity(0.4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
