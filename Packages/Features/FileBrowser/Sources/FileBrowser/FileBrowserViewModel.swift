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
    public private(set) var isLoading = false
    public private(set) var lastError: TransportError?

    private let browseFolderUseCase: BrowseFolderUseCase
    private let renameFileUseCase: RenameFileUseCase
    private let deleteFilesUseCase: DeleteFilesUseCase
    private let createFolderUseCase: CreateFolderUseCase

    public init(
        browseFolder: BrowseFolderUseCase,
        renameFile: RenameFileUseCase,
        deleteFiles: DeleteFilesUseCase,
        createFolder: CreateFolderUseCase
    ) {
        self.browseFolderUseCase = browseFolder
        self.renameFileUseCase = renameFile
        self.deleteFilesUseCase = deleteFiles
        self.createFolderUseCase = createFolder
    }

    public var breadcrumb: [String] {
        path.raw
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    public func navigate(to target: RemotePath) async {
        path = target
        selection.clear()
        await reload()
    }

    public func navigateUp() async {
        guard let parent = path.parent else { return }
        await navigate(to: parent)
    }

    public func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await browseFolderUseCase(path)
            entries = sort.apply(raw, ascending: sortAscending)
            lastError = nil
        } catch let error as TransportError {
            lastError = error
        } catch {
            lastError = .ioFailure(message: String(describing: error))
        }
    }

    public func setSort(_ option: FileSortOption) async {
        sort = option
        await reload()
    }

    public func toggleSortDirection() async {
        sortAscending.toggle()
        await reload()
    }

    public func toggleSelection(_ targetPath: RemotePath) {
        selection.toggle(targetPath)
    }

    public func selectOnly(_ targetPath: RemotePath) {
        selection.replace(with: targetPath)
    }

    public func clearSelection() {
        selection.clear()
    }

    public func deleteSelection() async {
        guard !selection.isEmpty else { return }
        do {
            try await deleteFilesUseCase(paths: Array(selection.paths))
            selection.clear()
            await reload()
        } catch let error as TransportError {
            lastError = error
        } catch {
            lastError = .ioFailure(message: String(describing: error))
        }
    }

    public func createFolder(named name: String) async {
        do {
            _ = try await createFolderUseCase(at: path, name: name)
            await reload()
        } catch let error as TransportError {
            lastError = error
        } catch {
            lastError = .ioFailure(message: String(describing: error))
        }
    }

    public func rename(_ targetPath: RemotePath, to newName: String) async {
        let parent = targetPath.parent ?? .root
        let dest = parent.appending(newName)
        do {
            try await renameFileUseCase(from: targetPath, to: dest)
            await reload()
        } catch let error as TransportError {
            lastError = error
        } catch {
            lastError = .ioFailure(message: String(describing: error))
        }
    }
}
