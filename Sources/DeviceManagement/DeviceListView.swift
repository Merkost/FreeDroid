import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct DeviceListView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: DeviceListViewModel
    var deviceFractions: [DeviceID: Double]
    var onRevealInFinder: (Device) -> Void

    public init(
        viewModel: DeviceListViewModel,
        deviceFractions: [DeviceID: Double] = [:],
        onRevealInFinder: @escaping (Device) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.deviceFractions = deviceFractions
        self.onRevealInFinder = onRevealInFinder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Devices")
                .font(Typography.label)
                .foregroundStyle(theme.colors.text2)
                .padding(.horizontal, Spacing.sm + 2)
                .padding(.top, Spacing.lg)
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
                                onRevealInFinder: { onRevealInFinder(device) }
                            )
                            .onTapGesture { viewModel.select(device.id) }
                            .motion(.crisp, value: viewModel.selectedID)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm + 2)
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

    var body: some View {
        DeviceCardView(
            viewModel: cardViewModel,
            isSelected: isSelected,
            onRevealInFinder: onRevealInFinder
        )
    }

    private var cardViewModel: DeviceCardViewModel {
        let vm = DeviceCardViewModel(device: device)
        if let fraction = transferFraction {
            vm.setTransferProgress(fraction)
        }
        return vm
    }
}
