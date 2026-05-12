import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct TransfersPanel: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: TransfersViewModel
    var deviceNameByID: (DeviceID) -> String?

    public init(viewModel: TransfersViewModel, deviceNameByID: @escaping (DeviceID) -> String?) {
        self.viewModel = viewModel
        self.deviceNameByID = deviceNameByID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Transfers").font(Typography.bodyEmphasized).foregroundStyle(theme.colors.text0)
                Spacer()
                Text("\(viewModel.states.count) active")
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
            }
            if viewModel.states.isEmpty {
                Text("No active transfers")
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
                    .padding(.vertical, Spacing.sm)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs + 2) {
                        ForEach(Array(viewModel.states.enumerated()), id: \.offset) { _, transferState in
                            TransferRow(
                                state: transferState,
                                deviceName: deviceName(for: transferState),
                                onCancel: {
                                    Task {
                                        if let jobID = jobID(in: transferState) {
                                            await viewModel.cancel(jobID)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(theme.colors.line, lineWidth: 1)
                )
        )
        .task { await viewModel.observe() }
    }

    private func jobID(in state: TransferState) -> UUID? {
        switch state {
        case .running(let transferProgress), .paused(let transferProgress): return transferProgress.jobID
        default: return nil
        }
    }

    private func deviceName(for state: TransferState) -> String? {
        guard let jobID = jobID(in: state),
              let deviceID = viewModel.jobToDevice[jobID] else { return nil }
        return deviceNameByID(deviceID)
    }
}
