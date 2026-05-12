import SwiftUI
import FreeDroidDomain
import FreeDroidUI

struct FileListSkeleton: View {
    private let placeholderWidths: [CGFloat] = [200, 140, 220, 160, 180, 130, 200, 150]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(placeholderWidths.indices, id: \.self) { index in
                FileRowSkeleton(nameWidth: placeholderWidths[index])
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

struct FileBrowserErrorCard: View {
    @Environment(\.theme) private var theme
    let error: TransportError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(theme.colors.warning)
            VStack(spacing: Spacing.xs) {
                Text("Couldn't load this folder")
                    .font(Typography.title)
                    .foregroundStyle(theme.colors.text0)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(theme.colors.text2)
                    .multilineTextAlignment(.center)
            }
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.warning)
                .disabled(!error.isRetryable && error != .cancelled)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.colors.background1.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(theme.colors.warning.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var message: String {
        switch error {
        case .notConnected: return "The device disconnected. Reconnect and try again."
        case .unauthorized: return "Permission was denied. Authorize the device on the phone."
        case .timeout: return "The device took too long to respond."
        case .ioFailure(let detail): return detail
        case .notFound(let path): return "Path not found: \(path.raw)"
        case .alreadyExists(let path): return "Already exists: \(path.raw)"
        case .unsupported(let reason): return reason
        case .cancelled: return "The operation was cancelled."
        }
    }
}
