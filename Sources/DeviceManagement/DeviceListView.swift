import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct DeviceListView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: DeviceListViewModel
    var deviceFractions: [DeviceID: Double]
    var onRevealInFinder: (Device) -> Void
    var onShowInFinder: (Device) -> Void
    var onAddWifi: (() -> Void)?

    public init(
        viewModel: DeviceListViewModel,
        deviceFractions: [DeviceID: Double] = [:],
        onRevealInFinder: @escaping (Device) -> Void = { _ in },
        onShowInFinder: @escaping (Device) -> Void = { _ in },
        onAddWifi: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.deviceFractions = deviceFractions
        self.onRevealInFinder = onRevealInFinder
        self.onShowInFinder = onShowInFinder
        self.onAddWifi = onAddWifi
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Devices")
                    .font(Typography.label)
                    .foregroundStyle(theme.colors.text2)
                Spacer()
                if let onAddWifi {
                    Button(action: onAddWifi) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.colors.text2)
                    }
                    .buttonStyle(.borderless)
                    .help("Pair Android phone over Wi-Fi")
                }
            }
            .padding(.horizontal, Spacing.sm + 2)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)
            ScrollView {
                LazyVStack(spacing: Spacing.xs + 2) {
                    if viewModel.devices.isEmpty {
                        DeviceEmptyState()
                    } else {
                        ForEach(viewModel.devices) { device in
                            DeviceCardRow(
                                device: device,
                                isSelected: device.id == viewModel.selectedID,
                                transferFraction: deviceFractions[device.id],
                                onRevealInFinder: { onRevealInFinder(device) },
                                onShowInFinder: { onShowInFinder(device) }
                            )
                            .id(device.id)
                            .onTapGesture { viewModel.select(device.id) }
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm + 2)
                .animation(.snappy(duration: 0.18), value: viewModel.devices.map(\.id))
            }
        }
        .frame(width: 280)
        .background(.regularMaterial)
        .task {
            await viewModel.observe()
        }
    }
}

private struct DeviceCardRow: View {
    let device: Device
    let isSelected: Bool
    let transferFraction: Double?
    let onRevealInFinder: () -> Void
    let onShowInFinder: () -> Void

    @State private var cardViewModel: DeviceCardViewModel?

    var body: some View {
        let vm = cardViewModel ?? DeviceCardViewModel(device: device)
        DeviceCardView(
            viewModel: vm,
            isSelected: isSelected,
            onRevealInFinder: onRevealInFinder,
            onShowInFinder: onShowInFinder
        )
        .task(id: device.id) {
            if cardViewModel == nil {
                cardViewModel = DeviceCardViewModel(device: device)
            }
        }
        .onChange(of: device) { _, new in
            cardViewModel?.update(device: new)
        }
        .onChange(of: transferFraction, initial: true) { _, new in
            guard let cardViewModel else { return }
            if let new {
                cardViewModel.setTransferProgress(new)
            } else {
                cardViewModel.clearTransferProgress()
            }
        }
    }
}
