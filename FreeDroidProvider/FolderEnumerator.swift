import FileProvider
import Foundation
import FreeDroidProviderShared

final class FolderEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {
    static let schemaVersion = "v3-mtime"
    private static let currentAnchor = NSFileProviderSyncAnchor(Data(schemaVersion.utf8))

    private let containerIdentifier: NSFileProviderItemIdentifier
    private let folderPath: RemotePath
    private let transport: ProviderTransport
    private let enumerationCache: EnumerationCache

    init(
        container: NSFileProviderItemIdentifier,
        folderPath: RemotePath,
        transport: ProviderTransport,
        enumerationCache: EnumerationCache
    ) {
        self.containerIdentifier = container
        self.folderPath = folderPath
        self.transport = transport
        self.enumerationCache = enumerationCache
        super.init()
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        nonisolated(unsafe) let obs = observer
        nonisolated(unsafe) let path = folderPath
        let cache = enumerationCache
        Task {
            do {
                let entries = try await transport.list(path)
                await cache.record(entries)
                let items: [NSFileProviderItem] = entries.map {
                    ProviderItem(entry: $0, parent: path)
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
        if anchor == Self.currentAnchor {
            observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
        } else {
            observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(Self.currentAnchor)
    }
}
