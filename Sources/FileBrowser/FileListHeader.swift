import SwiftUI
import FreeDroidUI

public struct FileListHeader: View {
    @Environment(\.theme) private var theme
    public let sort: FileSortOption
    public let ascending: Bool
    public let onSelect: (FileSortOption) -> Void

    private let iconColumnWidth: CGFloat = 24
    private let sizeColumnWidth: CGFloat = 96
    private let dateColumnWidth: CGFloat = 116
    private let chevronColumnWidth: CGFloat = 18

    public init(sort: FileSortOption, ascending: Bool, onSelect: @escaping (FileSortOption) -> Void) {
        self.sort = sort
        self.ascending = ascending
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: Spacing.md) {
            Color.clear.frame(width: iconColumnWidth, height: 1)
            headerButton(title: "Name", option: .name, alignment: .leading)
            Spacer(minLength: Spacing.sm)
            headerButton(title: "Size", option: .size, alignment: .trailing)
                .frame(width: sizeColumnWidth, alignment: .trailing)
            headerButton(title: "Modified", option: .modified, alignment: .trailing)
                .frame(width: dateColumnWidth, alignment: .trailing)
            Color.clear.frame(width: chevronColumnWidth, height: 1)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 26)
        .background(theme.colors.background1.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.line)
                .frame(height: 1)
        }
    }

    private func headerButton(title: String, option: FileSortOption, alignment: HorizontalAlignment) -> some View {
        Button {
            onSelect(option)
        } label: {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title)
                    .font(Typography.label)
                    .tracking(0.7)
                    .foregroundStyle(sort == option ? theme.colors.text0 : theme.colors.text2)
                if sort == option {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.colors.accent)
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .motion(.crisp, value: sort)
        .motion(.crisp, value: ascending)
    }
}
