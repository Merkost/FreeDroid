import SwiftUI
import FreeDroidUI

public struct TrustPromptSheet: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: TrustPromptViewModel
    var onDismiss: () -> Void

    public init(viewModel: TrustPromptViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Sheet {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(theme.colors.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trust this Mac").font(Typography.title)
                        Text("Check your phone — tap Allow to authorize USB debugging.")
                            .font(Typography.body)
                            .foregroundStyle(theme.colors.text1)
                    }
                }
                Divider().overlay(theme.colors.line)
                statusRow
                HStack {
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                    if viewModel.isAuthorized {
                        Button("Continue", action: onDismiss)
                            .buttonStyle(.borderedProminent)
                            .tint(theme.colors.accent)
                    }
                }
            }
        }
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: Spacing.sm + 2) {
            switch viewModel.status {
            case .waiting:
                Spinner()
                Text("Waiting for your phone…").font(Typography.body)
            case .authorized:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.accent)
                Text("Authorized").font(Typography.body)
            case .missing:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.colors.warning)
                Text("Device disconnected. Reconnect to retry.").font(Typography.body)
            case .error(let message):
                Image(systemName: "xmark.octagon").foregroundStyle(theme.colors.danger)
                Text(message).font(Typography.body)
            }
        }
    }
}
