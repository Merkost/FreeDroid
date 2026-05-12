import SwiftUI

public struct CommandStripAction: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let systemImage: String?
    public let hotkey: String?
    public let isPrimary: Bool
    public let action: @MainActor () -> Void

    public init(
        label: String,
        systemImage: String? = nil,
        hotkey: String? = nil,
        isPrimary: Bool = false,
        action: @escaping @MainActor () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.hotkey = hotkey
        self.isPrimary = isPrimary
        self.action = action
    }
}

public struct CommandStrip: View {
    @Environment(\.theme) private var theme
    private let selectionCount: Int
    private let actions: [CommandStripAction]

    public init(selectionCount: Int, actions: [CommandStripAction]) {
        self.selectionCount = selectionCount
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: 2) {
            if selectionCount > 0 {
                HStack(spacing: 6) {
                    Text("\(selectionCount)").font(Typography.numeral).foregroundStyle(theme.colors.text0)
                    Text("selected").font(Typography.caption).foregroundStyle(theme.colors.text2)
                }
                .padding(.horizontal, Spacing.sm)
                separator
            }
            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                button(for: action)
                if idx < actions.count - 1 && actions[idx + 1].isPrimary {
                    separator
                }
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: Radius.lg + 2, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg + 2, style: .continuous)
                        .strokeBorder(theme.colors.lineStrong, lineWidth: 1)
                )
        }
        .shadow(Shadows.floating)
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.colors.line)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func button(for action: CommandStripAction) -> some View {
        Button(action: action.action) {
            HStack(spacing: 7) {
                if let icon = action.systemImage {
                    Image(systemName: icon).font(.system(size: 13, weight: action.isPrimary ? .semibold : .medium))
                }
                Text(action.label).font(Typography.callout).fontWeight(action.isPrimary ? .semibold : .medium)
                if let hk = action.hotkey {
                    Hotkey(hk)
                }
            }
            .foregroundStyle(action.isPrimary ? Color(red: 0, green: 0.2, blue: 0.1) : theme.colors.text1)
            .padding(.horizontal, Spacing.md - 1)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md - 1, style: .continuous)
                    .fill(action.isPrimary ? theme.colors.accent : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
