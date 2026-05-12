import FileProvider
import FreeDroidProviderShared

final class FreeDroidProviderExtension: NSObject, NSFileProviderReplicatedExtension, @unchecked Sendable {
    let domain: NSFileProviderDomain
    let deviceID: DeviceID
    let transport: ProviderTransport

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.deviceID = DeviceID(raw: domain.identifier.rawValue)
        self.transport = ProviderTransport(deviceID: DeviceID(raw: domain.identifier.rawValue))
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
                handler(nil, ProviderError.map(error))
            } catch {
                handler(nil, error)
            }
        }
        return Progress()
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        nonisolated(unsafe) let handler = completionHandler
        nonisolated(unsafe) let progress = Progress(totalUnitCount: -1)
        Task {
            do {
                guard let path = ItemIdentifier.decode(itemIdentifier.rawValue) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                let session = try await transport.ensure()
                let entry = try await session.stat(path)
                let total = entry.sizeBytes ?? 0
                progress.totalUnitCount = total
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension((entry.name as NSString).pathExtension)
                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: tempURL)
                defer { try? handle.close() }
                let chunkSize = 1 << 20
                var offset: Int64 = 0
                while offset < total {
                    let length = Int(min(Int64(chunkSize), total - offset))
                    let chunk = try await session.read(path, offset: offset, length: length)
                    try handle.write(contentsOf: chunk)
                    offset += Int64(chunk.count)
                    progress.completedUnitCount = offset
                    if chunk.count == 0 { break }
                }
                let item = ProviderItem(entry: entry, parent: path.parent ?? .root)
                handler(tempURL, item, nil)
            } catch let error as TransportError {
                handler(nil, nil, ProviderError.map(error))
            } catch {
                handler(nil, nil, error)
            }
        }
        return progress
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        if containerItemIdentifier == .workingSet { return WorkingSetEnumerator() }
        if containerItemIdentifier == .trashContainer {
            throw NSFileProviderError(.noSuchItem)
        }
        let path = ItemIdentifier.decode(containerItemIdentifier.rawValue) ?? .root
        return FolderEnumerator(
            container: containerItemIdentifier,
            folderPath: path,
            transport: transport
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
        nonisolated(unsafe) let progress = Progress(totalUnitCount: 1)
        let parentIdentifier = itemTemplate.parentItemIdentifier
        let filename = itemTemplate.filename
        let contentType = itemTemplate.contentType
        Task {
            do {
                let parent = try resolveParent(parentIdentifier)
                let newPath = parent.appending(filename)
                let session = try await transport.ensure()
                if contentType == .folder {
                    try await session.mkdir(newPath)
                } else if let url {
                    let data = try Data(contentsOf: url)
                    try await session.write(newPath, data: data, offset: 0)
                } else {
                    try await session.write(newPath, data: Data(), offset: 0)
                }
                let entry = try await session.stat(newPath)
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
        nonisolated(unsafe) let progress = Progress(totalUnitCount: 1)
        let itemIdentifierRaw = item.itemIdentifier.rawValue
        let parentIdentifier = item.parentItemIdentifier
        let filename = item.filename
        Task {
            do {
                guard let path = ItemIdentifier.decode(itemIdentifierRaw) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                var currentPath = path
                let session = try await transport.ensure()

                if changedFields.contains(.parentItemIdentifier) || changedFields.contains(.filename) {
                    let newParent = try resolveParent(parentIdentifier)
                    let target = newParent.appending(filename)
                    if target != currentPath {
                        try await session.rename(currentPath, to: target)
                        currentPath = target
                    }
                }

                if changedFields.contains(.contents), let newContents {
                    let data = try Data(contentsOf: newContents)
                    try await session.write(currentPath, data: data, offset: 0)
                }

                let entry = try await session.stat(currentPath)
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
        nonisolated(unsafe) let progress = Progress(totalUnitCount: 1)
        let identifierRaw = identifier.rawValue
        Task {
            do {
                guard let path = ItemIdentifier.decode(identifierRaw) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                let session = try await transport.ensure()
                try await session.remove(path)
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
        if identifier == .rootContainer || identifier == .trashContainer {
            return ProviderItem.root(displayName: domain.displayName)
        }
        guard let path = ItemIdentifier.decode(identifier.rawValue) else {
            throw NSFileProviderError(.noSuchItem)
        }
        let session = try await transport.ensure()
        let entry = try await session.stat(path)
        let parent = path.parent ?? .root
        return ProviderItem(entry: entry, parent: parent)
    }
}
