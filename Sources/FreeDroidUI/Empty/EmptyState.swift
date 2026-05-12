import SwiftUI

public struct EmptyState: View {
    @Environment(\.theme) private var theme
    private let icon: String
    private let title: String
    private let message: String
    private let actionLabel: String?
    private let action: (@MainActor () -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionLabel: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.colors.text2)
            VStack(spacing: 4) {
                Text(title).font(Typography.title).foregroundStyle(theme.colors.text0)
                Text(message).font(Typography.body).foregroundStyle(theme.colors.text2).multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.colors.accent)
            }
        }
        .frame(maxWidth: 320)
        .padding(Spacing.xl)
    }
}
