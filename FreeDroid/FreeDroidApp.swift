import SwiftUI
import Sparkle

@MainActor
final class UpdaterController {
    let driver: SPUStandardUpdaterController

    init() {
        self.driver = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}

@main
struct FreeDroidApp: App {
    @State private var container = AppContainer()
    private let updater = UpdaterController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
                .frame(minWidth: 920, idealWidth: 1200, minHeight: 600, idealHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    updater.driver.checkForUpdates(nil)
                }
            }
        }

        MenuBarExtra {
            MenuBarStatusView()
                .environment(container)
        } label: {
            let count = container.deviceListViewModel.devices.filter { $0.connectionState == .ready }.count
            Image(systemName: count > 0 ? "iphone.gen3" : "iphone.gen3.slash")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(container)
        }
    }
}
