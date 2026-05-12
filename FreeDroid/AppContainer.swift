import Foundation
import Observation
import FSKit
import os.log
import FreeDroidDomain
import FreeDroidData
import FreeDroidADB
import FreeDroidMTP
import DeviceManagement
import FileBrowser
import Gallery
import Transfer

private let mountLogger = Logger(subsystem: "com.merkost.freedroid", category: "mount")

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
    let extensionMonitor = FSExtensionMonitor()

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
    }

    func fileBrowserViewModel(for deviceID: DeviceID) -> FileBrowserViewModel {
        let fileRepo = FileRepositoryImpl(registry: registry, cache: listingCache, deviceID: deviceID)
        return FileBrowserViewModel(
            initialPath: RemotePath(raw: "/sdcard"),
            browseFolder: BrowseFolderUseCase(fileRepository: fileRepo),
            renameFile: RenameFileUseCase(fileRepository: fileRepo),
            deleteFiles: DeleteFilesUseCase(fileRepository: fileRepo),
            createFolder: CreateFolderUseCase(fileRepository: fileRepo)
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
        extensionMonitor.start()
        await observeDevicesForMounting()
    }

    @available(macOS 15.4, *)
    private func observeDevicesForMounting() async {
        let logger = mountLogger
        let freedroidModuleID = "com.merkost.freedroid.FreeDroidFS"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            FSClient.shared.fetchInstalledExtensions { modules, error in
                defer { continuation.resume() }
                if let error {
                    logger.error("Mount failed: \(String(describing: error), privacy: .public)")
                    return
                }
                let found = modules?.contains { $0.bundleIdentifier == freedroidModuleID } ?? false
                if found {
                    logger.info("FreeDroidFS module found; awaiting entitlement for mount activation")
                } else {
                    logger.info("FreeDroidFS module not installed; mount stub — entitlement required")
                }
            }
        }
    }
}
