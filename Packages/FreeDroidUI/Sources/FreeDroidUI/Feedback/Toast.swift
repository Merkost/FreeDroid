import SwiftUI

public enum ToastKind: Sendable {
    case info, success, warning, danger
}

public struct Toast: View, Identifiable {
    public let id = UUID()
    @Environment(\.theme) private var theme
    private let kind: ToastKind
    private let title: String
    private let detail: String?

    public init(kind: ToastKind = .info, title: String, detail: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(spacing: Spacing.sm + 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.6), radius: 6)
            HStack(spacing: 6) {
                Text(title).font(Typography.callout).foregroundStyle(theme.colors.text0)
                if let detail {
                    Text(detail).font(Typography.captionEmphasized).foregroundStyle(theme.colors.text0)
                }
            }
        }
        .padding(.horizontal, Spacing.md + 2)
        .padding(.vertical, Spacing.sm + 1)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(theme.colors.lineStrong, lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
    }

    private var color: Color {
        switch kind {
        case .info: theme.colors.accent
        case .success: theme.colors.accent
        case .warning: theme.colors.warning
        case .danger: theme.colors.danger
        }
    }
}
