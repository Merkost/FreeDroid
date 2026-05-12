import Foundation
import FSKit
import FreeDroidDomain
import FreeDroidIPC
import os.log

private let logger = Logger(subsystem: "com.merkost.freedroid.FreeDroidFS", category: "volume")

final class FreeDroidVolume: FSVolume, FSVolume.Operations, FSVolume.ReadWriteOperations {
    let deviceID: DeviceID
    let client: XPCClient
    let cache = FreeDroidItemCache()
    private let displayName: String

    var supportedVolumeCapabilities: FSVolume.SupportedCapabilities {
        FSVolume.SupportedCapabilities()
    }

    var volumeStatistics: FSStatFSResult {
        FSStatFSResult(fileSystemTypeName: "freedroid")
    }

    var maximumLinkCount: Int { 1 }
    var maximumNameLength: Int { 255 }
    var restrictsOwnershipChanges: Bool { false }
    var truncatesLongNames: Bool { false }
    var maximumFileSize: UInt64 { UInt64.max }

    init(deviceID: DeviceID, displayName: String, client: XPCClient) {
        self.deviceID = deviceID
        self.client = client
        self.displayName = displayName
        let volID = VolumeIdentifierMint.identifier(for: deviceID.raw)
        let volName = FSFileName(string: displayName)
        super.init(volumeID: volID, volumeName: volName)
    }

    func mount(options: FSTaskOptions) async throws {
    }

    func unmount() async {
    }

    func synchronize(flags: FSSyncFlags) async throws {
    }

    func activate(options: FSTaskOptions) async throws -> FSItem {
        let rootEntry = RemoteEntry(
            path: .root,
            name: displayName,
            kind: .directory,
            sizeBytes: nil,
            modifiedAt: nil,
            isHidden: false
        )
        return FreeDroidItem(deviceID: deviceID, entry: rootEntry)
    }

    func deactivate(options: FSDeactivateOptions) async throws {
    }

    func attributes(
        _ request: FSItem.GetAttributesRequest,
        of item: FSItem
    ) async throws -> FSItem.Attributes {
        guard let fdItem = item as? FreeDroidItem else {
            return FSItem.Attributes()
        }
        let attrs = FSItem.Attributes()
        let entry = fdItem.entry
        if entry.kind == .directory {
            attrs.type = .directory
            attrs.mode = 0o755
        } else {
            attrs.type = .file
            attrs.mode = 0o644
        }
        attrs.linkCount = 1
        if let size = entry.sizeBytes {
            attrs.size = UInt64(max(0, size))
        }
        if let modified = entry.modifiedAt {
            var ts = timespec()
            ts.tv_sec = Int(modified.timeIntervalSince1970)
            ts.tv_nsec = 0
            attrs.modifyTime = ts
        }
        return attrs
    }

    func setAttributes(
        _ request: FSItem.SetAttributesRequest,
        on item: FSItem
    ) async throws -> FSItem.Attributes {
        FSItem.Attributes()
    }

    func lookupItem(
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> (FSItem, FSFileName) {
        guard let parent = directory as? FreeDroidItem else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        }
        let nameStr = name.string ?? ""
        let path = parent.entry.path.appending(nameStr)
        if let cached = await cache.get(path) {
            return (cached, FSFileName(string: nameStr))
        }
        do {
            let entry: RemoteEntry = try await client.send(
                .stat(deviceID: parent.deviceID, path: path),
                expecting: RemoteEntry.self
            )
            let resultItem = FreeDroidItem(deviceID: parent.deviceID, entry: entry)
            await cache.put(path, resultItem)
            return (resultItem, FSFileName(string: entry.name))
        } catch TransportError.notFound {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        }
    }

    func reclaimItem(_ item: FSItem) async throws {
    }

    func readSymbolicLink(_ item: FSItem) async throws -> FSFileName {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP))
    }

    func createItem(
        named name: FSFileName,
        type: FSItem.ItemType,
        inDirectory directory: FSItem,
        attributes: FSItem.SetAttributesRequest
    ) async throws -> (FSItem, FSFileName) {
        guard let parent = directory as? FreeDroidItem else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        }
        let nameStr = name.string ?? ""
        let path = parent.entry.path.appending(nameStr)
        if type == .directory {
            _ = try await client.send(.mkdir(deviceID: parent.deviceID, path: path), expecting: Data.self)
        } else {
            _ = try await client.send(
                .write(deviceID: parent.deviceID, path: path, data: Data(), offset: 0),
                expecting: Data.self
            )
        }
        let entry: RemoteEntry = try await client.send(
            .stat(deviceID: parent.deviceID, path: path),
            expecting: RemoteEntry.self
        )
        let newItem = FreeDroidItem(deviceID: parent.deviceID, entry: entry)
        await cache.invalidate(parent.entry.path)
        return (newItem, FSFileName(string: entry.name))
    }

    func createSymbolicLink(
        named name: FSFileName,
        inDirectory directory: FSItem,
        attributes: FSItem.SetAttributesRequest,
        linkContents: FSFileName
    ) async throws -> (FSItem, FSFileName) {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP))
    }

    func createLink(
        to item: FSItem,
        named name: FSFileName,
        inDirectory directory: FSItem
    ) async throws -> FSFileName {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP))
    }

    func removeItem(
        _ item: FSItem,
        named name: FSFileName,
        fromDirectory directory: FSItem
    ) async throws {
        guard let fdItem = item as? FreeDroidItem else { return }
        _ = try await client.send(.remove(deviceID: fdItem.deviceID, path: fdItem.entry.path), expecting: Data.self)
        if let parentPath = fdItem.entry.path.parent {
            await cache.invalidate(parentPath)
        }
    }

    // swiftlint:disable:next function_parameter_count
    func renameItem(
        _ item: FSItem,
        inDirectory sourceDirectory: FSItem,
        named sourceName: FSFileName,
        to destinationName: FSFileName,
        inDirectory destinationDirectory: FSItem,
        overItem: FSItem?
    ) async throws -> FSFileName {
        guard let fdItem = item as? FreeDroidItem else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        }
        let destParent: RemotePath
        if let destDir = destinationDirectory as? FreeDroidItem {
            destParent = destDir.entry.path
        } else {
            destParent = fdItem.entry.path.parent ?? .root
        }
        let destNameStr = destinationName.string ?? ""
        let destPath = destParent.appending(destNameStr)
        _ = try await client.send(
            .rename(deviceID: fdItem.deviceID, from: fdItem.entry.path, to: destPath),
            expecting: Data.self
        )
        if let sourceParent = fdItem.entry.path.parent {
            await cache.invalidate(sourceParent)
        }
        await cache.invalidate(destParent)
        return FSFileName(string: destNameStr)
    }

    func enumerateDirectory(
        _ directory: FSItem,
        startingAt cookie: FSDirectoryCookie,
        verifier: FSDirectoryVerifier,
        attributes: FSItem.GetAttributesRequest?,
        packer: FSDirectoryEntryPacker
    ) async throws -> FSDirectoryVerifier {
        guard let fdDir = directory as? FreeDroidItem else {
            return FSDirectoryVerifier(1)
        }
        if attributes == nil {
            _ = packer.packEntry(
                name: FSFileName(string: "."),
                itemType: .directory,
                itemID: .rootDirectory,
                nextCookie: FSDirectoryCookie.initial,
                attributes: nil
            )
            _ = packer.packEntry(
                name: FSFileName(string: ".."),
                itemType: .directory,
                itemID: .parentOfRoot,
                nextCookie: FSDirectoryCookie.initial,
                attributes: nil
            )
        }
        do {
            let enumerator = DirectoryEnumerator(directory: fdDir, client: client)
            let entries = try await enumerator.fetchAll()
            var itemID: UInt64 = 100
            let startIndex = Int(cookie.rawValue)
            for (index, entry) in entries.enumerated() {
                if index < startIndex { continue }
                let childPath = fdDir.entry.path.appending(entry.name)
                let childItem = FreeDroidItem(deviceID: fdDir.deviceID, entry: entry)
                await cache.put(childPath, childItem)
                let itemType: FSItem.ItemType = entry.kind == .directory ? .directory : .file
                let nextCookieValue = FSDirectoryCookie(rawValue: UInt64(index + 1))
                let rawID = FSItem.Identifier(rawValue: itemID) ?? .rootDirectory
                let packed = packer.packEntry(
                    name: FSFileName(string: entry.name),
                    itemType: itemType,
                    itemID: rawID,
                    nextCookie: nextCookieValue,
                    attributes: nil
                )
                itemID += 1
                if !packed { break }
            }
        } catch {
            logger.error("Enumerate failed: \(String(describing: error), privacy: .public)")
        }
        return FSDirectoryVerifier(1)
    }

}

extension FreeDroidVolume {
    func read(
        from item: FSItem,
        at offset: off_t,
        length: Int,
        into buffer: FSMutableFileDataBuffer
    ) async throws -> Int {
        guard let fdItem = item as? FreeDroidItem else { return 0 }
        let data: Data = try await client.send(
            .read(deviceID: fdItem.deviceID, path: fdItem.entry.path, offset: Int64(offset), length: length),
            expecting: Data.self
        )
        let count = min(data.count, buffer.length)
        buffer.withUnsafeMutableBytes { rawBuffer in
            data.withUnsafeBytes { dataBuffer in
                rawBuffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: dataBuffer.prefix(count)))
            }
        }
        return count
    }

    func write(
        contents data: Data,
        to item: FSItem,
        at offset: off_t
    ) async throws -> Int {
        guard let fdItem = item as? FreeDroidItem else { return 0 }
        _ = try await client.send(
            .write(deviceID: fdItem.deviceID, path: fdItem.entry.path, data: data, offset: Int64(offset)),
            expecting: Data.self
        )
        if let parentPath = fdItem.entry.path.parent {
            await cache.invalidate(parentPath)
        }
        return data.count
    }
}
