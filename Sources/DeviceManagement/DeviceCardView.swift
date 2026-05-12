import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct DeviceCardView: View {
    @Environment(\.theme) private var theme
    private let viewModel: DeviceCardViewModel
    private let isSelected: Bool
    private let onRevealInFinder: () -> Void
    private let onShowInFinder: () -> Void

    public init(
        viewModel: DeviceCardViewModel,
        isSelected: Bool,
        onRevealInFinder: @escaping () -> Void,
        onShowInFinder: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.isSelected = isSelected
        self.onRevealInFinder = onRevealInFinder
        self.onShowInFinder = onShowInFinder
    }

    public var body: some View {
        Card(isActive: isSelected && viewModel.isReady) {
            ZStack(alignment: .bottom) {
                if let fraction = viewModel.transferFraction {
                    FluidProgress(fraction: fraction)
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md - 1) {
                        LivingRing(color: color, state: viewModel.ringState, glyph: viewModel.glyph)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.name)
                                .font(Typography.bodyEmphasized)
                                .foregroundStyle(theme.colors.text0)
                                .lineLimit(1)
                            if let subtitle = viewModel.subtitle {
                                Text(subtitle)
                                    .font(Typography.caption)
                                    .foregroundStyle(theme.colors.text2)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        IconChip(viewModel.transportLabel, kind: viewModel.transportKind)
                    }
                    if let hint = viewModel.statusHint {
                        Text(hint)
                            .font(Typography.caption)
                            .foregroundStyle(theme.colors.warning)
                            .lineLimit(2)
                    } else if viewModel.isReady {
                        readyFooter
                    }
                }
                .padding(Spacing.xs + 2)
            }
        }
        .opacity(viewModel.isReady ? 1.0 : 0.65)
        .allowsHitTesting(viewModel.isReady || isSelected)
        .contextMenu {
            Button("Show in Finder") {
                onShowInFinder()
            }
            Button("Reveal Transfers in Finder") {
                onRevealInFinder()
            }
        }
    }

    private var readyFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let storage = viewModel.storageDescription {
                Text(storage)
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
            }
            if let fraction = viewModel.storageFraction {
                StorageBar(fraction: fraction, tint: color)
            }
            HStack(spacing: Spacing.xs) {
                Button {
                    onShowInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .font(Typography.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.colors.accent)
                Spacer(minLength: 0)
            }
        }
    }

    private struct StorageBar: View {
        @Environment(\.theme) private var theme
        let fraction: Double
        let tint: Color

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.colors.line)
                    Capsule()
                        .fill(tint.opacity(0.7))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
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
