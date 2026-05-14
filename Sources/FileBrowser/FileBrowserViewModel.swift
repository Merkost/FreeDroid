import Foundation
import Observation
import FreeDroidDomain

@MainActor
@Observable
public final class FileBrowserViewModel {
    public private(set) var entries: [RemoteEntry] = []
    public private(set) var path: RemotePath = .root
    public var sort: FileSortOption = .name
    public var sortAscending: Bool = true
    public var selection = FileBrowserSelection()
    public var focusedPath: RemotePath?
    public private(set) var isLoading = false
    public private(set) var loadStartedAt: Date?
    public private(set) var lastError: TransportError?
    public private(set) var inspectedEntry: RemoteEntry?
    public private(set) var inspectorPreviewURL: URL?
    public private(set) var inspectorIsPreparing = false
    public let deviceID: DeviceID?

    private let browseFolderUseCase: BrowseFolderUseCase
    private let renameFileUseCase: RenameFileUseCase
    private let deleteFilesUseCase: DeleteFilesUseCase
    private let createFolderUseCase: CreateFolderUseCase
    private let downloadToTempUseCase: DownloadToTempUseCase?
    private var inspectorTask: Task<Void, Never>?
    private let inspectorAutoPreviewByteLimit: Int64 = 12 * 1024 * 1024

    public init(
        initialPath: RemotePath = .root,
        browseFolder: BrowseFolderUseCase,
        renameFile: RenameFileUseCase,
        deleteFiles: DeleteFilesUseCase,
        createFolder: CreateFolderUseCase,
        downloadToTemp: DownloadToTempUseCase? = nil,
        deviceID: DeviceID? = nil
    ) {
        self.path = initialPath
        self.browseFolderUseCase = browseFolder
        self.renameFileUseCase = renameFile
        self.deleteFilesUseCase = deleteFiles
        self.createFolderUseCase = createFolder
        self.downloadToTempUseCase = downloadToTemp
        self.deviceID = deviceID
    }

    public func inspect(_ entry: RemoteEntry?) {
        inspectorTask?.cancel()
        inspectorTask = nil
        inspectorPreviewURL = nil
        inspectorIsPreparing = false
        inspectedEntry = entry
        guard let entry, entry.kind == .file, let downloader = downloadToTempUseCase else { return }
        guard QuickLookEligibility.isInlinePreviewable(entry.name) else { return }
        let size = entry.sizeBytes ?? Int64.max
        guard size <= inspectorAutoPreviewByteLimit else { return }
        inspectorIsPreparing = true
        let targetPath = entry.path
        let task = Task { [weak self, entry] in
            let url = try? await downloader(entry: entry)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.inspectedEntry?.path == targetPath else { return }
            self.inspectorPreviewURL = url
            self.inspectorIsPreparing = false
        }
        inspectorTask = task
    }

    public func openInspectedFile() async -> URL? {
        guard let entry = inspectedEntry, let downloader = downloadToTempUseCase else { return nil }
        if let cached = inspectorPreviewURL { return cached }
        inspectorIsPreparing = true
        defer { inspectorIsPreparing = false }
        do {
            let url = try await downloader(entry: entry)
            inspectorPreviewURL = url
            return url
        } catch {
            return nil
        }
    }

    public var breadcrumb: [String] {
        path.raw
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    public var hasError: Bool { lastError != nil }

    public func navigate(to target: RemotePath) async {
        path = target
        selection.clear()
        focusedPath = nil
        await reload()
    }

    public func navigateUp() async {
        guard let parent = path.parent else { return }
        await navigate(to: parent)
    }

    public func reload() async {
        isLoading = true
        loadStartedAt = Date()
        defer {
            isLoading = false
            loadStartedAt = nil
        }
        do {
            let raw = try await browseFolderUseCase(path)
            entries = sort.apply(raw, ascending: sortAscending)
            lastError = nil
            if let focused = focusedPath, !entries.contains(where: { $0.path == focused }) {
                focusedPath = entries.first?.path
            } else if focusedPath == nil {
                focusedPath = entries.first?.path
            }
        } catch {
            recordError(error)
        }
    }

    private func recordError(_ error: Error) {
        if let transport = error as? TransportError {
            lastError = transport
        } else {
            lastError = .ioFailure(message: String(describing: error))
        }
    }

    public func setSort(_ option: FileSortOption) {
        if sort == option {
            sortAscending.toggle()
        } else {
            sort = option
        }
        entries = sort.apply(entries, ascending: sortAscending)
    }

    public func toggleSortDirection() {
        sortAscending.toggle()
        entries = sort.apply(entries, ascending: sortAscending)
    }

    public func toggleSelection(_ targetPath: RemotePath) {
        selection.toggle(targetPath)
        focusedPath = targetPath
    }

    public func selectOnly(_ targetPath: RemotePath) {
        selection.replace(with: targetPath)
        focusedPath = targetPath
    }

    public func extendSelection(to targetPath: RemotePath) {
        guard let anchor = selection.anchor ?? focusedPath,
              let anchorIndex = entries.firstIndex(where: { $0.path == anchor }),
              let targetIndex = entries.firstIndex(where: { $0.path == targetPath }) else {
            selectOnly(targetPath)
            return
        }
        let bounds = anchorIndex <= targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
        let pathsInRange = Set(entries[bounds].map(\.path))
        selection.replace(with: pathsInRange, anchor: anchor)
        focusedPath = targetPath
    }

    public func selectAll() {
        let all = Set(entries.map(\.path))
        selection.replace(with: all, anchor: entries.first?.path)
        focusedPath = entries.last?.path
    }

    public func clearSelection() {
        selection.clear()
    }

    public func focusFirst() {
        focusedPath = entries.first?.path
    }

    public func moveFocus(by offset: Int) {
        guard !entries.isEmpty else { return }
        let currentIndex = focusedPath.flatMap { focused in entries.firstIndex(where: { $0.path == focused }) } ?? -1
        let nextIndex = max(0, min(entries.count - 1, currentIndex + offset))
        focusedPath = entries[nextIndex].path
    }

    public func extendFocus(by offset: Int) {
        guard !entries.isEmpty else { return }
        let currentIndex = focusedPath.flatMap { focused in entries.firstIndex(where: { $0.path == focused }) } ?? 0
        let nextIndex = max(0, min(entries.count - 1, currentIndex + offset))
        let nextPath = entries[nextIndex].path
        extendSelection(to: nextPath)
    }

    public func activateFocused() async {
        guard let focused = focusedPath,
              let entry = entries.first(where: { $0.path == focused }) else { return }
        if entry.kind == .directory {
            await navigate(to: entry.path)
        } else {
            toggleSelection(entry.path)
        }
    }

    public func deleteSelection() async {
        guard !selection.isEmpty else { return }
        let toDelete = Array(selection.paths)
        do {
            try await deleteFilesUseCase(paths: toDelete)
            let removed = Set(toDelete)
            entries.removeAll { removed.contains($0.path) }
            selection.clear()
            if let focused = focusedPath, removed.contains(focused) {
                focusedPath = entries.first?.path
            }
        } catch {
            recordError(error)
        }
    }

    public func createFolder(named name: String) async {
        do {
            _ = try await createFolderUseCase(at: path, name: name)
            await reload()
        } catch {
            recordError(error)
        }
    }

    public func rename(_ targetPath: RemotePath, to newName: String) async {
        let parent = targetPath.parent ?? .root
        let dest = parent.appending(newName)
        do {
            try await renameFileUseCase(from: targetPath, to: dest)
            await reload()
        } catch {
            recordError(error)
        }
    }
}
