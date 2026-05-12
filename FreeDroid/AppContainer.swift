import Foundation
import Observation

@MainActor
@Observable
final class AppContainer {
    let bundleVersion: String

    init() {
        self.bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
