import Foundation
import CLibmtp
import FreeDroidDomain

public actor MTPSession: Transport {
    public let deviceID: DeviceID
    public let capabilities = TransportCapabilities(
        supportsRangeRead: false,
        supportsRangeWrite: false,
        supportsSymlinks: false,
        recommendedChunkBytes: 4 * 1024 * 1024
    )

    private let raw: MTPRawDevice
    private let quirks: MTPQuirks
    private let keepalive = MTPKeepalive()
    private var device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>?
    private var resolver: MTPPathResolver?
    private var cachedInfo: DeviceInfo?

    public init(deviceID: DeviceID, raw: MTPRawDevice) {
        self.deviceID = deviceID
        self.raw = raw
        self.quirks = MTPQuirks.for(vendorID: raw.vendorID, productID: raw.productID)
    }

    public var info: DeviceInfo {
        get async throws {
            if let cachedInfo { return cachedInfo }
            let dev = try openIfNeeded()
            let manufacturer: String
            if let ptr = LIBMTP_Get_Manufacturername(dev) {
                manufacturer = String(cString: ptr)
                free(ptr)
            } else {
                manufacturer = raw.vendorName ?? "Unknown"
            }
            let model: String
            if let ptr = LIBMTP_Get_Modelname(dev) {
                model = String(cString: ptr)
                free(ptr)
            } else {
                model = raw.productName ?? "Unknown"
            }
            let serial: String
            if let ptr = LIBMTP_Get_Serialnumber(dev) {
                serial = String(cString: ptr)
                free(ptr)
            } else {
                serial = raw.identifier
            }
            let result = DeviceInfo(
                serial: serial,
                manufacturer: manufacturer,
                model: model,
                androidVersion: nil,
                storageCapacityBytes: nil,
                storageFreeBytes: nil
            )
            cachedInfo = result
            return result
        }
    }

    public func list(_ path: RemotePath) async throws -> [RemoteEntry] {
        try refreshResolverIfNeeded()
        guard let res = resolver else { throw TransportError.notConnected }
        return res.children(of: path).map { obj in
            RemoteEntry(
                path: path.appending(obj.name),
                name: obj.name,
                kind: obj.isFolder ? .directory : .file,
                sizeBytes: obj.isFolder ? nil : obj.size,
                modifiedAt: obj.modifiedAt,
                isHidden: obj.name.hasPrefix(".")
            )
        }
    }

    public func stat(_ path: RemotePath) async throws -> RemoteEntry {
        let parent = path.parent ?? .root
        let entries = try await list(parent)
        guard let match = entries.first(where: { $0.name == path.name }) else {
            throw TransportError.notFound(path)
        }
        return match
    }

    public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
        try refreshResolverIfNeeded()
        guard let dev = device, let res = resolver else { throw TransportError.notConnected }
        guard let handle = res.handle(for: path), handle != 0 else { throw TransportError.notFound(path) }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("freedroid-mtp-\(UUID().uuidString)", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        let status = MTPStderrSilencer.run {
            temp.withUnsafeFileSystemRepresentation { cstr -> Int32 in
                LIBMTP_Get_File_To_File(dev, handle, cstr, nil, nil)
            }
        }
        if status != 0 {
            throw MTPSessionError.operationFailed(message: "Get_File_To_File=\(status)").toTransportError()
        }
        let data = try Data(contentsOf: temp)
        let start = Int(offset)
        let end = min(start + length, data.count)
        guard start < data.count else { return Data() }
        return data.subdata(in: start..<end)
    }

    public func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
        guard offset == 0 else {
            throw TransportError.unsupported(reason: "MTP write does not support offset writes")
        }
        guard data.count <= quirks.maxWriteChunkBytes else {
            throw TransportError.unsupported(
                reason: "Chunked writes pending; max chunk = \(quirks.maxWriteChunkBytes)"
            )
        }
        try refreshResolverIfNeeded()
        guard let dev = device, let res = resolver else { throw TransportError.notConnected }
        let parent = path.parent ?? .root
        guard let parentHandle = res.handle(for: parent) else { throw TransportError.notFound(parent) }
        let storageID: UInt32 = res.objects.first(where: { $0.objectHandle == parentHandle })?.storageID
            ?? res.objects.first?.storageID ?? 0
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("freedroid-mtp-up-\(UUID().uuidString)", isDirectory: false)
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        var meta = LIBMTP_file_t()
        let nameBuf = strdup(path.name)
        meta.filename = nameBuf
        defer { free(nameBuf) }
        meta.filesize = UInt64(data.count)
        meta.parent_id = parentHandle
        meta.storage_id = storageID
        let status = MTPStderrSilencer.run {
            temp.withUnsafeFileSystemRepresentation { cstr -> Int32 in
                LIBMTP_Send_File_From_File(dev, cstr, &meta, nil, nil)
            }
        }
        if status != 0 {
            throw MTPSessionError.operationFailed(message: "Send_File_From_File=\(status)").toTransportError()
        }
        try refreshResolver()
    }

    public func mkdir(_ path: RemotePath) async throws {
        try refreshResolverIfNeeded()
        guard let dev = device, let res = resolver else { throw TransportError.notConnected }
        let parent = path.parent ?? .root
        guard let parentHandle = res.handle(for: parent) else { throw TransportError.notFound(parent) }
        let storageID: UInt32 = res.objects.first(where: { $0.objectHandle == parentHandle })?.storageID
            ?? res.objects.first?.storageID ?? 0
        let nameBuf = strdup(path.name)
        defer { free(nameBuf) }
        let newID = MTPStderrSilencer.run { LIBMTP_Create_Folder(dev, nameBuf, parentHandle, storageID) }
        if newID == 0 {
            throw MTPSessionError.operationFailed(message: "Create_Folder failed").toTransportError()
        }
        try refreshResolver()
    }

    public func remove(_ path: RemotePath) async throws {
        try refreshResolverIfNeeded()
        guard let dev = device, let res = resolver else { throw TransportError.notConnected }
        guard let handle = res.handle(for: path), handle != 0 else { throw TransportError.notFound(path) }
        let status = MTPStderrSilencer.run { LIBMTP_Delete_Object(dev, handle) }
        if status != 0 {
            throw MTPSessionError.operationFailed(message: "Delete_Object=\(status)").toTransportError()
        }
        try refreshResolver()
    }

    public func rename(_ from: RemotePath, to destination: RemotePath) async throws {
        guard from.parent == destination.parent else {
            throw TransportError.unsupported(
                reason: "Cross-directory MTP rename via temp+remove not yet implemented"
            )
        }
        try refreshResolverIfNeeded()
        guard let dev = device, let res = resolver else { throw TransportError.notConnected }
        guard let handle = res.handle(for: from), handle != 0 else { throw TransportError.notFound(from) }
        var folder = LIBMTP_folder_t()
        folder.folder_id = handle
        let nameBuf = strdup(destination.name)
        defer { free(nameBuf) }
        let status = MTPStderrSilencer.run { LIBMTP_Set_Folder_Name(dev, &folder, nameBuf) }
        if status != 0 {
            throw MTPSessionError.operationFailed(message: "Set_Folder_Name=\(status)").toTransportError()
        }
        try refreshResolver()
    }

    public func close() async {
        await keepalive.stop()
        if let dev = device {
            LIBMTP_Release_Device(dev)
            self.device = nil
        }
        resolver = nil
        cachedInfo = nil
    }

    // MARK: - Private helpers

    private func openIfNeeded() throws -> UnsafeMutablePointer<LIBMTP_mtpdevice_t> {
        if let dev = device { return dev }
        var rawCopy = LIBMTP_raw_device_t()
        rawCopy.device_entry.vendor_id = raw.vendorID
        rawCopy.device_entry.product_id = raw.productID
        rawCopy.bus_location = raw.busLocation
        rawCopy.devnum = raw.devnum
        guard let dev = MTPStderrSilencer.run({ LIBMTP_Open_Raw_Device_Uncached(&rawCopy) }) else {
            throw MTPSessionError.openFailed(message: "device returned nil").toTransportError()
        }
        self.device = dev
        if quirks.requiresKeepalive {
            Task { [weak self] in
                guard let self else { return }
                await self.startKeepalive()
            }
        }
        return dev
    }

    private func startKeepalive() async {
        guard quirks.requiresKeepalive else { return }
        await keepalive.start(interval: .seconds(quirks.keepaliveIntervalSeconds)) { [weak self] in
            guard let self else { return }
            await self.pingDevice()
        }
    }

    private func pingDevice() async {
        guard let dev = device else { return }
        let ptr = LIBMTP_Get_Manufacturername(dev)
        free(ptr)
    }

}

extension MTPSession {
    fileprivate func refreshResolverIfNeeded() throws {
        if resolver == nil { try refreshResolver() }
    }

    fileprivate func refreshResolver() throws {
        let dev = try openIfNeeded()
        let head: UnsafeMutablePointer<LIBMTP_file_t>? = MTPStderrSilencer.run {
            LIBMTP_Get_Filelisting_With_Callback(dev, nil, nil)
        }
        defer {
            var cursor = head
            while let node = cursor {
                let next = node.pointee.next
                LIBMTP_destroy_file_t(node)
                cursor = next
            }
        }
        var collected: [MTPObject] = []
        var cursor = head
        while let node = cursor {
            let fileEntry = node.pointee
            let name = fileEntry.filename.map { String(cString: $0) } ?? ""
            collected.append(MTPObject(
                storageID: fileEntry.storage_id,
                objectHandle: fileEntry.item_id,
                parentHandle: fileEntry.parent_id,
                name: name,
                isFolder: fileEntry.filetype == LIBMTP_FILETYPE_FOLDER,
                size: Int64(fileEntry.filesize),
                modifiedAt: fileEntry.modificationdate > 0
                    ? Date(timeIntervalSince1970: TimeInterval(fileEntry.modificationdate))
                    : nil
            ))
            cursor = fileEntry.next
        }
        resolver = MTPPathResolver(objects: collected)
    }
}
