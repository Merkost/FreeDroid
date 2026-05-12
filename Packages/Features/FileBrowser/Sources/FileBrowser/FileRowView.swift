import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct FileRowView: View {
    @Environment(\.theme) private var theme
    public let entry: RemoteEntry
    public let isSelected: Bool

    public init(entry: RemoteEntry, isSelected: Bool) {
        self.entry = entry
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: Spacing.md - 2) {
            Image(systemName: FileIconResolver.symbol(for: entry))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.text1)
                .frame(width: 20)
            Text(entry.name)
                .font(Typography.body)
                .foregroundStyle(theme.colors.text0)
                .lineLimit(1)
            Spacer()
            if entry.kind != .directory, let size = entry.sizeBytes {
                Text(ByteCountFormatter().string(fromByteCount: size))
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
                    .frame(width: 100, alignment: .trailing)
            } else {
                Text("—")
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text3)
                    .frame(width: 100, alignment: .trailing)
            }
            if let mtime = entry.modifiedAt {
                Text(mtime.formatted(.dateTime.month().day().year(.twoDigits).hour().minute()))
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
                    .frame(width: 130, alignment: .trailing)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs + 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? theme.colors.accentSoft : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(isSelected ? theme.colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
