import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct BreadcrumbBar: View {
    @Environment(\.theme) private var theme
    private let components: [String]
    private let onSelect: (RemotePath) -> Void

    public init(components: [String], onSelect: @escaping (RemotePath) -> Void) {
        self.components = components
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            crumb(label: "/", path: .root)
            ForEach(Array(components.enumerated()), id: \.offset) { idx, name in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.colors.text3)
                let segmentPath = RemotePath(raw: "/" + components[0...idx].joined(separator: "/"))
                crumb(label: name, path: segmentPath, isCurrent: idx == components.count - 1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func crumb(label: String, path: RemotePath, isCurrent: Bool = false) -> some View {
        Button {
            onSelect(path)
        } label: {
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(isCurrent ? theme.colors.text0 : theme.colors.text1)
                .fontWeight(isCurrent ? .medium : .regular)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isCurrent ? theme.colors.line : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
