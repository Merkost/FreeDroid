import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct TransferRow: View {
    @Environment(\.theme) private var theme
    public let state: TransferState
    public let deviceName: String?
    public let onCancel: () -> Void

    public init(state: TransferState, deviceName: String? = nil, onCancel: @escaping () -> Void) {
        self.state = state
        self.deviceName = deviceName
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: Spacing.md - 2) {
            statusIndicator
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typography.bodyEmphasized).foregroundStyle(theme.colors.text0)
                if let subtitle {
                    Text(subtitle).font(Typography.caption).foregroundStyle(theme.colors.text2)
                }
            }
            Spacer()
            if case .running = state {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(theme.colors.text2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm + 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.colors.background1.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(theme.colors.line, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch state {
        case .running(let transferProgress):
            Spinner(size: 16)
                .overlay(Text("\(Int(transferProgress.fraction * 100))").font(Typography.monoCaption))
        case .paused:
            Image(systemName: "pause.circle").foregroundStyle(theme.colors.warning)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.accent)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(theme.colors.danger)
        case .idle:
            Image(systemName: "circle.dotted").foregroundStyle(theme.colors.text2)
        }
    }

    private var title: String {
        switch state {
        case .running(let transferProgress):
            let total = ByteCountFormatter().string(fromByteCount: transferProgress.totalBytes)
            return "Copying · \(total) total"
        case .paused: return "Paused"
        case .completed: return "Complete"
        case .failed(let error): return "Failed · \(error)"
        case .idle: return "Idle"
        }
    }

    private var subtitle: String? {
        deviceName
    }
}
