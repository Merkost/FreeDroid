import SwiftUI

public struct PillTabs<Tab: Hashable & Sendable>: View {
    @Environment(\.theme) private var theme
    @Binding private var selection: Tab
    private let tabs: [(label: String, value: Tab)]

    public init(selection: Binding<Tab>, tabs: [(String, Tab)]) {
        self._selection = selection
        self.tabs = tabs
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.value) { tab in
                let isActive = tab.value == selection
                Button {
                    selection = tab.value
                } label: {
                    Text(tab.label)
                        .font(Typography.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(isActive ? theme.colors.text0 : theme.colors.text2)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs + 1)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(isActive ? theme.colors.line : .clear)
                        )
                }
                .buttonStyle(.plain)
                .motion(.crisp, value: isActive)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.colors.background1.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(theme.colors.line, lineWidth: 1)
                )
        )
    }
}
