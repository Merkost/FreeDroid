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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    updater.driver.checkForUpdates(nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(container)
        }
    }
}
