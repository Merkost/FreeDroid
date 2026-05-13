import AppKit
import FileProvider
import FreeDroidDomain

enum ProviderRevealer {
    @MainActor
    static func revealInFinder(deviceID: DeviceID) async {
        let identifier = NSFileProviderDomainIdentifier(deviceID.raw)
        let domain = NSFileProviderDomain(identifier: identifier, displayName: "")
        guard let manager = NSFileProviderManager(for: domain) else {
            NSWorkspace.shared.activateFileViewerSelecting([])
            return
        }
        do {
            let url = try await manager.getUserVisibleURL(for: .rootContainer)
            NSWorkspace.shared.open(url)
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting([])
        }
    }
}
