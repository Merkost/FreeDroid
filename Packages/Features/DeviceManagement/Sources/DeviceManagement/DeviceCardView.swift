import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct DeviceCardView: View {
    @Environment(\.theme) private var theme
    private let viewModel: DeviceCardViewModel
    private let isSelected: Bool

    public init(viewModel: DeviceCardViewModel, isSelected: Bool) {
        self.viewModel = viewModel
        self.isSelected = isSelected
    }

    public var body: some View {
        Card(isActive: isSelected) {
            ZStack(alignment: .bottom) {
                if let fraction = viewModel.transferFraction {
                    FluidProgress(fraction: fraction)
                }
                HStack(spacing: Spacing.md - 1) {
                    LivingRing(color: color, state: viewModel.ringState, glyph: viewModel.glyph)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.name)
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(theme.colors.text0)
                            .lineLimit(1)
                        HStack(spacing: Spacing.xs + 2) {
                            if let capacity = viewModel.capacityDescription {
                                Text(capacity)
                                    .font(Typography.caption)
                                    .foregroundStyle(theme.colors.text2)
                            }
                            IconChip(viewModel.transportLabel, kind: viewModel.transportKind)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.xs + 2)
            }
        }
    }

    private var color: Color {
        switch viewModel.transportKind {
        case .adb: theme.colors.adb
        case .mtp: theme.colors.mtp
        case .wifi: theme.colors.wifi
        case .off: theme.colors.text2
        case .custom(let customColor): customColor
        }
    }
}
