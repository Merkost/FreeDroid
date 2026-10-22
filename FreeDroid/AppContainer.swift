import Foundation
import Observation
import os.log
import FreeDroidDomain
import FreeDroidData
import FreeDroidADB
import FreeDroidMTP
import DeviceManagement
import FileBrowser
import Gallery
import Transfer

struct StorageCandidate: Identifiable, Hashable {
    let id: RemotePath
    let path: RemotePath
    let sizeBytes: Int64
    let modifiedAt: Date?

    var name: String { path.name }
}

@MainActor
@Observable
final class AppContainer {
    let bundleVersion: String
    let preferences = AppPreferences()

    let adbServer: ADBServer
    let mtpRuntime = MTPRuntime()
    let mtpDiscovery: MTPDeviceDiscovery
    let pinPreference = DevicePinPreference()
    let usbWatcher = USBDeviceWatcher()
    let listingCache = ListingCache()
    let thumbnailCache: ThumbnailCache
    let registry: DeviceRegistry
    let deviceRepository: DeviceRepositoryImpl
    let deviceListViewModel: DeviceListViewModel

    let transferQueue = TransferQueue()
    let transferDestinations = DownloadsTransferDestinationProvider()
    let transferRepository: TransferRepositoryImpl
    let transfersViewModel: TransfersViewModel
    let transferToastPresenter = TransferToastPresenter()

    let xpcRegistry = XPCConnectionRegistry()
    let domainCoordinator: ProviderDomainCoordinator
    let wifiStore = WifiEndpointStore()
    let wifiCoordinator: WifiADBCoordinator

    init() {
        self.bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        do {
            let server = try ADBServer.liveSync()
            self.adbServer = server
        } catch {
            fatalError("Failed to initialize ADB server: \(error)")
        }
        self.mtpDiscovery = MTPDeviceDiscovery(runtime: mtpRuntime)
        let thumbsURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeDroid/thumbs", isDirectory: true)
        self.thumbnailCache = ThumbnailCache(rootURL: thumbsURL)
        self.registry = DeviceRegistry(
            adbServer: adbServer,
            mtpRuntime: mtpRuntime,
            mtpDiscovery: mtpDiscovery,
            pinPreference: pinPreference,
            usbWatcher: usbWatcher
        )
        self.deviceRepository = DeviceRepositoryImpl(registry: registry)
        self.deviceListViewModel = DeviceListViewModel(repository: deviceRepository)
        self.transferRepository = TransferRepositoryImpl(queue: transferQueue, registry: registry)
        self.transfersViewModel = TransfersViewModel(
            repository: transferRepository,
            cancel: CancelTransferUseCase(repository: transferRepository)
        )
        self.domainCoordinator = ProviderDomainCoordinator(registry: registry)
        self.wifiCoordinator = WifiADBCoordinator(adbServer: adbServer, store: wifiStore)
    }

    func pair(host: String, port: Int, code: String) async throws {
        try await wifiCoordinator.pair(host: host, port: port, code: code)
    }

    func disconnectWifi(_ endpoint: WifiEndpoint) async throws {
        try await wifiCoordinator.disconnect(endpoint)
    }

    func installAPK(from source: URL, on deviceID: DeviceID) async throws {
        try await registry.installAPK(from: source, on: deviceID)
    }

    func uploadFiles(_ urls: [URL], to deviceIDs: Set<DeviceID>) async throws {
        for deviceID in deviceIDs {
            let fileRepo = FileRepositoryImpl(registry: registry, cache: listingCache, deviceID: deviceID)
            let uploader = UploadFileUseCase(fileRepository: fileRepo)
            for url in urls {
                try await uploader(source: url, destinationFolder: RemotePath(raw: "/sdcard/Download"))
            }
        }
    }

    func diagnose(_ deviceID: DeviceID) async -> [DiagnosticCheck] {
        var checks: [DiagnosticCheck] = []
        guard let device = await registry.device(deviceID),
              let transport = await registry.transport(for: deviceID) else {
            return [DiagnosticCheck(
                id: "connection",
                title: "Device connection",
                detail: "Device is no longer available.",
                status: .failed
            )]
        }
        checks.append(DiagnosticCheck(
            id: "connection",
            title: "Device connection",
            detail: "(device.displayName) is connected via (device.transport).",
            status: device.connectionState == .ready ? .passed : .warning
        ))
        do {
            let info = try await transport.info
            let version = info.androidVersion ?? "unknown Android version"
            checks.append(DiagnosticCheck(
                id: "adb",
                title: "ADB communication",
                detail: "(info.model), (version).",
                status: .passed
            ))
            if let capacity = info.storageCapacityBytes, let free = info.storageFreeBytes {
                let formatter = ByteCountFormatter()
                checks.append(DiagnosticCheck(
                    id: "storage",
                    title: "Storage",
                    detail: "(formatter.string(fromByteCount: free)) free of (formatter.string(fromByteCount: capacity)).",
                    status: free > 256 * 1024 * 1024 ? .passed : .warning
                ))
            }
        } catch {
            checks.append(DiagnosticCheck(
                id: "adb",
                title: "ADB communication",
                detail: String(describing: error),
                status: .failed
            ))
        }
        do {
            _ = try await transport.list(RemotePath(raw: "/sdcard"))
            checks.append(DiagnosticCheck(
                id: "storage-access",
                title: "User storage access",
                detail: "The Quest storage root is readable.",
                status: .passed
            ))
        } catch {
            checks.append(DiagnosticCheck(
                id: "storage-access",
                title: "User storage access",
                detail: String(describing: error),
                status: .failed
            ))
        }
        do {
            _ = try await transport.list(RemotePath(raw: "/sdcard/Download"))
            checks.append(DiagnosticCheck(
                id: "download",
                title: "Download folder",
                detail: "Download is accessible and ready for transfers.",
                status: .passed
            ))
        } catch {
            checks.append(DiagnosticCheck(
                id: "download",
                title: "Download folder",
                detail: "Download is not readable: \(error)",
                status: .warning
            ))
        }
        return checks
    }

    func storageCandidates(for deviceID: DeviceID, limit: Int = 200) async throws -> [StorageCandidate] {
        guard let transport = await registry.transport(for: deviceID) else {
            throw TransportError.notFound(RemotePath(raw: deviceID.raw))
        }
        let roots = ["Download", "Movies", "Pictures", "DCIM"].map { RemotePath(raw: "/sdcard/\($0)") }
        var candidates: [StorageCandidate] = []
        var queue = roots.map { ($0, 0) }
        var visited = Set<RemotePath>()
        while let (folder, depth) = queue.popLast(), candidates.count < limit * 4 {
            guard visited.insert(folder).inserted, depth <= 6 else { continue }
            for entry in try await transport.list(folder) {
                guard !entry.isHidden else { continue }
                switch entry.kind {
                case .directory:
                    if depth < 6 { queue.append((entry.path, depth + 1)) }
                case .file:
                    candidates.append(StorageCandidate(id: entry.path, path: entry.path, sizeBytes: entry.sizeBytes ?? 0, modifiedAt: entry.modifiedAt))
                case .symlink:
                    continue
                }
            }
        }
        return Array(candidates.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }

    func deleteStorageCandidates(_ candidates: [StorageCandidate], on deviceID: DeviceID) async throws {
        guard let transport = await registry.transport(for: deviceID) else {
            throw TransportError.notFound(RemotePath(raw: deviceID.raw))
        }
        for candidate in candidates {
            guard ["/sdcard/Download/", "/sdcard/Movies/", "/sdcard/Pictures/", "/sdcard/DCIM/"].contains(where: { candidate.path.raw.hasPrefix($0) }) else { continue }
            try await transport.remove(candidate.path)
        }
    }

    func fileBrowserViewModel(for deviceID: DeviceID) -> FileBrowserViewModel {
        let fileRepo = FileRepositoryImpl(registry: registry, cache: listingCache, deviceID: deviceID)
        return FileBrowserViewModel(
            initialPath: RemotePath(raw: "/sdcard"),
            browseFolder: BrowseFolderUseCase(fileRepository: fileRepo),
            renameFile: RenameFileUseCase(fileRepository: fileRepo),
            deleteFiles: DeleteFilesUseCase(fileRepository: fileRepo),
            createFolder: CreateFolderUseCase(fileRepository: fileRepo),
            downloadToTemp: DownloadToTempUseCase(fileRepository: fileRepo),
            uploadFile: UploadFileUseCase(fileRepository: fileRepo),
            deviceID: deviceID
        )
    }

    func galleryViewModel(for deviceID: DeviceID) -> GalleryViewModel {
        let fileRepo = FileRepositoryImpl(registry: registry, cache: listingCache, deviceID: deviceID)
        let mediaRepo = MediaRepositoryImpl(
            registry: registry,
            fileRepo: fileRepo,
            thumbnails: thumbnailCache,
            deviceID: deviceID
        )
        return GalleryViewModel(
            folder: RemotePath(raw: "/sdcard/DCIM/Camera"),
            loadMedia: LoadMediaUseCase(mediaRepository: mediaRepo),
            loadThumbnail: LoadThumbnailUseCase(mediaRepository: mediaRepo)
        )
    }

    func startTransferUseCase() -> StartTransferUseCase {
        StartTransferUseCase(repository: transferRepository, destinations: transferDestinations)
    }

    func start() async {
        try? await registry.start()
        xpcRegistry.start(registry: registry)
        domainCoordinator.start()
        await wifiCoordinator.start()
    }
}
