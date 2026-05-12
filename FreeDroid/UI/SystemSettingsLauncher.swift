import Foundation
import AppKit

@MainActor
enum SystemSettingsLauncher {
    static func openLoginItemsAndExtensions() {
        let urlString = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openPrivacyAndSecurity() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
