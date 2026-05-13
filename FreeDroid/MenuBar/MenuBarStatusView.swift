import SwiftUI
import FileProvider
import FreeDroidDomain
import FreeDroidUI
import DeviceManagement

struct MenuBarStatusView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let readyDevices = container.deviceListViewModel.devices.filter { $0.connectionState == .ready }
        let waitingDevices = container.deviceListViewModel.devices.filter { $0.connectionState != .ready }

        if readyDevices.isEmpty && waitingDevices.isEmpty {
            Text("No devices connected")
        } else {
            ForEach(readyDevices) { device in
                Button {
                    revealInFinder(deviceID: device.id, displayName: device.displayName)
                } label: {
                    Label(device.displayName, systemImage: device.transport == .adb ? "iphone" : "externaldrive")
                }
            }
            if !readyDevices.isEmpty && !waitingDevices.isEmpty { Divider() }
            ForEach(waitingDevices) { device in
                Text("\(device.displayName) — \(statusLabel(device.connectionState))")
                    .foregroundStyle(.secondary)
            }
        }
        Divider()
        Button("Open FreeDroid") { openMainWindow() }
            .keyboardShortcut("o")
        Divider()
        Button("Quit FreeDroid") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    private func revealInFinder(deviceID: DeviceID, displayName: String) {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(deviceID.raw),
            displayName: displayName
        )
        guard let manager = NSFileProviderManager(for: domain) else { return }
        manager.getUserVisibleURL(for: .rootContainer) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func statusLabel(_ state: DeviceConnectionState) -> String {
        switch state {
        case .ready: return "Ready"
        case .pendingAuthorization: return "Tap Allow on phone"
        case .chargingOnly: return "USB charging only"
        }
    }
}
