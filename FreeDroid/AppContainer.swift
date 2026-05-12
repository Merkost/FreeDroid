import Foundation
import Observation
import FreeDroidDomain
import FreeDroidData
import FreeDroidADB
import FreeDroidMTP
import DeviceManagement
import FileBrowser

@MainActor
@Observable
final class AppContainer {
    let bundleVersion: String

    let adbServer: ADBServer
    let mtpRuntime = MTPRuntime()
    let mtpDiscovery: MTPDeviceDiscovery
    let pinPreference = DevicePinPreference()
    let listingCache = ListingCache()
    let thumbnailCache: ThumbnailCache
    let registry: DeviceRegistry
    let deviceRepository: DeviceRepositoryImpl
    let deviceListViewModel: DeviceListViewModel

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
            pinPreference: pinPreference
        )
        self.deviceRepository = DeviceRepositoryImpl(registry: registry)
        self.deviceListViewModel = DeviceListViewModel(repository: deviceRepository)
    }

    func fileBrowserViewModel(for deviceID: DeviceID) -> FileBrowserViewModel {
        let fileRepo = FileRepositoryImpl(registry: registry, cache: listingCache, deviceID: deviceID)
        return FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: fileRepo),
            renameFile: RenameFileUseCase(fileRepository: fileRepo),
            deleteFiles: DeleteFilesUseCase(fileRepository: fileRepo),
            createFolder: CreateFolderUseCase(fileRepository: fileRepo)
        )
    }

    func start() async {
        try? await registry.start()
    }
}
