import SwiftUI

public struct Hotkey: View {
    @Environment(\.theme) private var theme
    private let symbols: String

    public init(_ symbols: String) {
        self.symbols = symbols
    }

    public var body: some View {
        Text(symbols)
            .font(Typography.monoCaption)
            .foregroundStyle(theme.colors.text2)
            .padding(.horizontal, Spacing.xs + 1)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(theme.colors.line)
            )
    }
}
