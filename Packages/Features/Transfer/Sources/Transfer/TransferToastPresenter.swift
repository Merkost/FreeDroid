import Foundation
import Observation
import FreeDroidDomain
import FreeDroidUI

@MainActor
@Observable
public final class TransferToastPresenter {
    public private(set) var toasts: [Toast] = []

    public init() {}

    public func consume(_ states: [TransferState]) {
        for state in states {
            switch state {
            case .completed:
                push(kind: .success, title: "Transfer complete")
            case .failed(let error):
                push(kind: .danger, title: "Transfer failed", detail: shortMessage(error))
            default:
                continue
            }
        }
    }

    private func push(kind: ToastKind, title: String, detail: String? = nil) {
        let toast = Toast(kind: kind, title: title, detail: detail)
        toasts.append(toast)
        let removeID = toast.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.toasts.removeAll { $0.id == removeID }
        }
    }

    private func shortMessage(_ error: TransportError) -> String {
        switch error {
        case .notConnected: "Device disconnected"
        case .unauthorized: "Unauthorized"
        case .timeout: "Timed out"
        case .ioFailure(let message): message
        case .notFound: "File not found"
        case .alreadyExists: "Already exists"
        case .unsupported(let reason): reason
        case .cancelled: "Cancelled"
        }
    }
}
