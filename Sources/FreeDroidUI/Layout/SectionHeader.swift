import SwiftUI

public struct SectionHeader: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.sm + 2) {
            Text(title).font(Typography.title).foregroundStyle(theme.colors.text0)
            if let detail {
                Text(detail).font(Typography.monoCaption).foregroundStyle(theme.colors.text2)
            }
            Spacer()
        }
    }
}
