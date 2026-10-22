import Foundation
import Observation
import FreeDroidDomain
import FreeDroidUI
import UserNotifications

@MainActor
@Observable
public final class TransferToastPresenter {
    public private(set) var toasts: [Toast] = []

    public init() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    public func consume(_ states: [TransferState]) {
        for state in states {
            switch state {
            case .completed:
                push(kind: .success, title: "Transfer complete")
                notify(title: "FreeDroid", body: "Transfer complete")
            case .failed(let error):
                push(kind: .danger, title: "Transfer failed", detail: shortMessage(error))
                notify(title: "FreeDroid", body: "Transfer failed: \(shortMessage(error))")
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

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
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
