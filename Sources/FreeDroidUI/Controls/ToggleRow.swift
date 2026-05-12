import SwiftUI

public struct ToggleRow: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.bodyEmphasized).foregroundStyle(theme.colors.text0)
                if let subtitle {
                    Text(subtitle).font(Typography.callout).foregroundStyle(theme.colors.text2)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(theme.colors.accent)
        }
        .padding(Spacing.md)
    }
}
