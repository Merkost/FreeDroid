import FileProvider
import FreeDroidContentCache
import FreeDroidProviderShared

final class FreeDroidProviderExtension: NSObject, NSFileProviderReplicatedExtension, @unchecked Sendable {
    let domain: NSFileProviderDomain
    let deviceID: DeviceID
    let transport: ProviderTransport
    let cache: ContentCache
    let enumerationCache: EnumerationCache
    let fetchGate: FetchGate

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let deviceID = DeviceID(raw: domain.identifier.rawValue)
        self.deviceID = deviceID
        self.transport = ProviderTransport(deviceID: deviceID)
        self.cache = ContentCache()
        self.enumerationCache = EnumerationCache()
        self.fetchGate = FetchGate(limit: FetchGate.defaultLimit())
        super.init()
    }

    func invalidate() {
        Task { await transport.invalidate() }
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        nonisolated(unsafe) let handler = completionHandler
        Task {
            do {
                let item = try await resolveItem(for: identifier)
                handler(item, nil)
            } catch let error as TransportError {
                await self.invalidateIfMissing(error: error, identifier: identifier)
                handler(nil, ProviderError.map(error))
            } catch {
                handler(nil, error)
            }
        }
        return Progress()
    }

    private func invalidateIfMissing(error: TransportError, identifier: NSFileProviderItemIdentifier) async {
        guard case .notFound(let path) = error else { return }
        await enumerationCache.invalidate(path)
        if let parent = path.parent {
            signalEnumerator(forParent: parent)
        }
    }

    private func signalEnumerator(forParent parent: RemotePath) {
        let parentIdentifier: NSFileProviderItemIdentifier = parent.isRoot
            ? .rootContainer
            : NSFileProviderItemIdentifier(ItemIdentifier.encode(parent))
        guard let manager = NSFileProviderManager(for: domain) else { return }
        manager.signalEnumerator(for: parentIdentifier) { _ in }
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        nonisolated(unsafe) let handler = completionHandler
        let progress = Progress(totalUnitCount: -1)
        Task {
            do {
                let result = try await self.fetchGate.withSlot {
                    try await self.materialize(itemIdentifier: itemIdentifier, progress: progress)
                }
                handler(result.url, result.item, nil)
            } catch let error as TransportError {
                await self.invalidateIfMissing(error: error, identifier: itemIdentifier)
                handler(nil, nil, ProviderError.map(error))
            } catch {
                handler(nil, nil, error)
            }
        }
        return progress
    }

    private struct MaterializeResult: @unchecked Sendable {
        let url: URL
        let item: ProviderItem
    }

    private func materialize(
        itemIdentifier: NSFileProviderItemIdentifier,
        progress: Progress
    ) async throws -> MaterializeResult {
        guard let path = ItemIdentifier.decode(itemIdentifier.rawValue) else {
            throw NSFileProviderError(.noSuchItem)
        }
        let entry = try await resolveEntry(at: path)
        progress.totalUnitCount = entry.sizeBytes ?? -1
        let parent = path.parent ?? .root
        let ext = (entry.name as NSString).pathExtension
        let key = ContentKey(
            deviceID: deviceID.raw,
            path: path.raw,
            mtimeUnix: Int64(entry.modifiedAt?.timeIntervalSince1970 ?? 0),
            size: entry.sizeBytes ?? 0
        )
        if let hit = await cache.lookup(key) {
            let cachedURL = IPCEndpoint.newTransferURL(filenameExtension: ext)
            try Self.materializeCached(from: hit, to: cachedURL)
            progress.completedUnitCount = entry.sizeBytes ?? 0
            return MaterializeResult(url: cachedURL, item: ProviderItem(entry: entry, parent: parent))
        }
        let tempURL = IPCEndpoint.newTransferURL(filenameExtension: ext)
        try await transport.fetch(path, into: tempURL)
        let finalSize = Self.fileSize(at: tempURL)
        if progress.totalUnitCount < 0 { progress.totalUnitCount = finalSize }
        progress.completedUnitCount = finalSize
        let finalKey = ContentKey(
            deviceID: deviceID.raw,
            path: path.raw,
            mtimeUnix: Int64(entry.modifiedAt?.timeIntervalSince1970 ?? 0),
            size: entry.sizeBytes ?? finalSize
        )
        _ = try? await cache.store(tempURL, key: finalKey, filename: entry.name)
        return MaterializeResult(url: tempURL, item: ProviderItem(entry: entry, parent: parent))
    }

    private func resolveEntry(at path: RemotePath) async throws -> RemoteEntry {
        if let cached = await enumerationCache.lookup(path) { return cached }
        let fresh = try await transport.stat(path)
        await enumerationCache.record([fresh])
        return fresh
    }

    private static func materializeCached(from hit: URL, to destination: URL) throws {
        try? FileManager.default.linkItem(at: hit, to: destination)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: hit, to: destination)
        }
    }

    private static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        if containerItemIdentifier == .workingSet { return WorkingSetEnumerator() }
        if containerItemIdentifier == .trashContainer { return WorkingSetEnumerator() }
        let path = ItemIdentifier.decode(containerItemIdentifier.rawValue) ?? .root
        return FolderEnumerator(
            container: containerItemIdentifier,
            folderPath: path,
            transport: transport,
            enumerationCache: enumerationCache
        )
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        nonisolated(unsafe) let handler = completionHandler
        let progress = Progress(totalUnitCount: 1)
        let parentIdentifier = itemTemplate.parentItemIdentifier
        let filename = itemTemplate.filename
        let contentType = itemTemplate.contentType
        if parentIdentifier == .trashContainer {
            handler(nil, [], false, NSFileProviderError(.noSuchItem))
            return progress
        }
        Task {
            do {
                let parent = try resolveParent(parentIdentifier)
                let newPath = parent.appending(filename)
                if contentType == .folder {
                    try await transport.mkdir(newPath)
                } else if let url {
                    let data = try Data(contentsOf: url)
                    try await transport.write(newPath, data: data, offset: 0)
                } else {
                    try await transport.write(newPath, data: Data(), offset: 0)
                }
                let entry = try await transport.stat(newPath)
                progress.completedUnitCount = 1
                handler(ProviderItem(entry: entry, parent: parent), [], false, nil)
            } catch let error as TransportError {
                handler(nil, [], false, ProviderError.map(error))
            } catch {
                handler(nil, [], false, error)
            }
        }
        return progress
    }

    private func resolveParent(_ identifier: NSFileProviderItemIdentifier) throws -> RemotePath {
        if identifier == .rootContainer { return .root }
        guard let path = ItemIdentifier.decode(identifier.rawValue) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return path
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        nonisolated(unsafe) let handler = completionHandler
        let progress = Progress(totalUnitCount: 1)
        let itemIdentifierRaw = item.itemIdentifier.rawValue
        let parentIdentifier = item.parentItemIdentifier
        let filename = item.filename
        if parentIdentifier == .trashContainer {
            handler(nil, [], false, NSFileProviderError(.noSuchItem))
            return progress
        }
        Task {
            do {
                guard let path = ItemIdentifier.decode(itemIdentifierRaw) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                var currentPath = path

                if changedFields.contains(.parentItemIdentifier) || changedFields.contains(.filename) {
                    let newParent = try resolveParent(parentIdentifier)
                    let target = newParent.appending(filename)
                    if target != currentPath {
                        try await transport.rename(currentPath, to: target)
                        currentPath = target
                    }
                }

                if changedFields.contains(.contents), let newContents {
                    let data = try Data(contentsOf: newContents)
                    try await transport.write(currentPath, data: data, offset: 0)
                }

                let entry = try await transport.stat(currentPath)
                progress.completedUnitCount = 1
                handler(ProviderItem(entry: entry, parent: currentPath.parent ?? .root), [], false, nil)
            } catch let error as TransportError {
                handler(nil, [], false, ProviderError.map(error))
            } catch {
                handler(nil, [], false, error)
            }
        }
        return progress
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        nonisolated(unsafe) let handler = completionHandler
        let progress = Progress(totalUnitCount: 1)
        let identifierRaw = identifier.rawValue
        Task {
            do {
                guard let path = ItemIdentifier.decode(identifierRaw) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                try await transport.remove(path)
                progress.completedUnitCount = 1
                handler(nil)
            } catch let error as TransportError {
                handler(ProviderError.map(error))
            } catch {
                handler(error)
            }
        }
        return progress
    }

    private func resolveItem(for identifier: NSFileProviderItemIdentifier) async throws -> NSFileProviderItem {
        if identifier == .rootContainer {
            return ProviderItem.root(displayName: domain.displayName)
        }
        if identifier == .trashContainer {
            return ProviderItem.trash()
        }
        guard let path = ItemIdentifier.decode(identifier.rawValue) else {
            throw NSFileProviderError(.noSuchItem)
        }
        let parent = path.parent ?? .root
        if let cached = await enumerationCache.lookup(path) {
            return ProviderItem(entry: cached, parent: parent)
        }
        let entry = try await transport.stat(path)
        await enumerationCache.record([entry])
        return ProviderItem(entry: entry, parent: parent)
    }
}
