import SwiftUI
import FreeDroidUI

@MainActor
@Observable
final class WifiPairSheetViewModel {
    var address: String = ""
    var pairingCode: String = ""
    var isWorking = false
    var result: PairResult?

    enum PairResult: Equatable {
        case success
        case failure(String)
    }

    var canPair: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty &&
        !pairingCode.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isWorking
    }

    func parsedHostPort() -> (host: String, port: Int)? {
        let raw = address.trimmingCharacters(in: .whitespaces)
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let port = Int(parts[1]), port > 0, port <= 65535 else { return nil }
        return (String(parts[0]), port)
    }

    func pair(using coordinator: WifiADBCoordinator) async {
        guard let (host, port) = parsedHostPort() else {
            result = .failure(WifiADBError.invalidAddress.localizedDescription ?? "Invalid address")
            return
        }
        isWorking = true
        result = nil
        do {
            try await coordinator.pair(host: host, port: port, code: pairingCode.trimmingCharacters(in: .whitespaces))
            result = .success
        } catch {
            result = .failure(error.localizedDescription)
        }
        isWorking = false
    }
}

struct WifiPairSheet: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: WifiPairSheetViewModel
    let coordinator: WifiADBCoordinator
    var onDismiss: () -> Void

    var body: some View {
        Sheet {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "wifi")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(theme.colors.wifi)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pair over Wi-Fi").font(Typography.title)
                        Text("On your phone go to Developer options → Wireless debugging → Pair device with pairing code.")
                            .font(Typography.body)
                            .foregroundStyle(theme.colors.text1)
                    }
                }
                Divider().overlay(theme.colors.line)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("IP address & port")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(theme.colors.text2)
                    TextField("192.168.1.5:37561", text: $viewModel.address)
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.body)
                        .disabled(viewModel.isWorking)
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Pairing code")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(theme.colors.text2)
                    TextField("123456", text: $viewModel.pairingCode)
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.body)
                        .disabled(viewModel.isWorking)
                }
                if let result = viewModel.result {
                    resultRow(result)
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: onDismiss)
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isWorking)
                    Button {
                        Task { await viewModel.pair(using: coordinator) }
                    } label: {
                        if viewModel.isWorking {
                            HStack(spacing: Spacing.xs) {
                                Spinner(size: 14)
                                Text("Pairing\u{2026}")
                            }
                        } else {
                            Text("Pair")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.colors.wifi)
                    .disabled(!viewModel.canPair)
                }
            }
        }
        .onChange(of: viewModel.result) { _, new in
            if case .success = new {
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    onDismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ result: WifiPairSheetViewModel.PairResult) -> some View {
        HStack(spacing: Spacing.sm) {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.accent)
                Text("Paired and connected.").font(Typography.body)
            case .failure(let msg):
                Image(systemName: "xmark.octagon").foregroundStyle(theme.colors.danger)
                Text(msg).font(Typography.body).foregroundStyle(theme.colors.danger)
            }
        }
    }
}
