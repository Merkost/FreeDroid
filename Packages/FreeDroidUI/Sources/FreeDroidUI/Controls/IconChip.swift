import SwiftUI

public enum IconChipKind: Sendable, Equatable {
    case adb, mtp, wifi, off, custom(Color)
}

public struct IconChip: View {
    @Environment(\.theme) private var theme
    private let label: String
    private let kind: IconChipKind

    public init(_ label: String, kind: IconChipKind) {
        self.label = label
        self.kind = kind
    }

    public var body: some View {
        Text(label.uppercased())
            .font(Typography.captionEmphasized)
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.xs + 1)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }

    private var color: Color {
        switch kind {
        case .adb: theme.colors.adb
        case .mtp: theme.colors.mtp
        case .wifi: theme.colors.wifi
        case .off: theme.colors.text2
        case .custom(let colorValue): colorValue
        }
    }
}
