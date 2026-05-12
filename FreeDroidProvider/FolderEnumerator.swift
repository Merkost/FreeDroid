import FileProvider
import Foundation
import FreeDroidProviderShared

final class FolderEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {
    private let containerIdentifier: NSFileProviderItemIdentifier
    private let folderPath: RemotePath
    private let deviceID: DeviceID
    private let bridge: XPCBridge

    init(
        container: NSFileProviderItemIdentifier,
        folderPath: RemotePath,
        deviceID: DeviceID,
        bridge: XPCBridge
    ) {
        self.containerIdentifier = container
        self.folderPath = folderPath
        self.deviceID = deviceID
        self.bridge = bridge
        super.init()
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        nonisolated(unsafe) let obs = observer
        Task {
            do {
                let entries = try await bridge.send(
                    .list(deviceID: deviceID, path: folderPath),
                    expecting: [RemoteEntry].self
                )
                let items: [NSFileProviderItem] = entries.map {
                    ProviderItem(entry: $0, parent: folderPath)
                }
                obs.didEnumerate(items)
                obs.finishEnumerating(upTo: nil)
            } catch let error as TransportError {
                obs.finishEnumeratingWithError(ProviderError.map(error))
            } catch {
                obs.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("v0".utf8)))
    }
}
