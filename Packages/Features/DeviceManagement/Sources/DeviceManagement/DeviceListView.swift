import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct DeviceListView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: DeviceListViewModel

    public init(viewModel: DeviceListViewModel) {
        self.viewModel = viewModel
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
                            let cardViewModel = DeviceCardViewModel(device: device)
                            DeviceCardView(
                                viewModel: cardViewModel,
                                isSelected: device.id == viewModel.selectedID
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
