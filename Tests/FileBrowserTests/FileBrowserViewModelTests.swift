import Foundation
import Testing
import FreeDroidDomain
@testable import FileBrowser

actor StubFileRepository: FileRepository {
    var entries: [RemotePath: [RemoteEntry]] = [:]

    func list(_ path: RemotePath) async throws -> [RemoteEntry] {
        entries[path] ?? []
    }

    func stat(_ path: RemotePath) async throws -> RemoteEntry {
        throw TransportError.notFound(path)
    }

    func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data { Data() }
    func write(_ path: RemotePath, data: Data, offset: Int64) async throws {}

    func mkdir(_ path: RemotePath) async throws {
        let parent = path.parent ?? .root
        entries[parent, default: []].append(
            RemoteEntry(
                path: path,
                name: path.name,
                kind: .directory,
                sizeBytes: nil,
                modifiedAt: nil,
                isHidden: false
            )
        )
    }

    func remove(_ path: RemotePath) async throws {
        let parent = path.parent ?? .root
        entries[parent]?.removeAll { $0.path == path }
    }

    func rename(_ from: RemotePath, to destination: RemotePath) async throws {}

    func seed(_ path: RemotePath, _ items: [RemoteEntry]) async {
        entries[path] = items
    }
}

@MainActor
@Suite("FileBrowserViewModel")
struct FileBrowserViewModelTests {
    private func entry(_ name: String, kind: EntryKind = .file) -> RemoteEntry {
        RemoteEntry(
            path: RemotePath(raw: "/sdcard/\(name)"),
            name: name,
            kind: kind,
            sizeBytes: 100,
            modifiedAt: nil,
            isHidden: false
        )
    }

    @Test func loadFolderPopulatesEntries() async throws {
        let repo = StubFileRepository()
        await repo.seed(RemotePath(raw: "/sdcard"), [entry("DCIM", kind: .directory), entry("photo.jpg")])
        let viewModel = FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: repo),
            renameFile: RenameFileUseCase(fileRepository: repo),
            deleteFiles: DeleteFilesUseCase(fileRepository: repo),
            createFolder: CreateFolderUseCase(fileRepository: repo)
        )
        await viewModel.navigate(to: RemotePath(raw: "/sdcard"))
        #expect(viewModel.entries.count == 2)
        #expect(viewModel.entries.first?.kind == .directory)
    }

    @Test func navigateUpdatesBreadcrumb() async {
        let repo = StubFileRepository()
        await repo.seed(RemotePath(raw: "/sdcard/DCIM"), [])
        let viewModel = FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: repo),
            renameFile: RenameFileUseCase(fileRepository: repo),
            deleteFiles: DeleteFilesUseCase(fileRepository: repo),
            createFolder: CreateFolderUseCase(fileRepository: repo)
        )
        await viewModel.navigate(to: RemotePath(raw: "/sdcard/DCIM"))
        #expect(viewModel.breadcrumb == ["sdcard", "DCIM"])
    }

    @Test func toggleSelection() async {
        let repo = StubFileRepository()
        await repo.seed(RemotePath(raw: "/x"), [
            RemoteEntry(
                path: RemotePath(raw: "/x/a"),
                name: "a",
                kind: .file,
                sizeBytes: 100,
                modifiedAt: nil,
                isHidden: false
            ),
            RemoteEntry(
                path: RemotePath(raw: "/x/b"),
                name: "b",
                kind: .file,
                sizeBytes: 100,
                modifiedAt: nil,
                isHidden: false
            )
        ])
        let viewModel = FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: repo),
            renameFile: RenameFileUseCase(fileRepository: repo),
            deleteFiles: DeleteFilesUseCase(fileRepository: repo),
            createFolder: CreateFolderUseCase(fileRepository: repo)
        )
        await viewModel.navigate(to: RemotePath(raw: "/x"))
        viewModel.toggleSelection(RemotePath(raw: "/x/a"))
        #expect(viewModel.selection.count == 1)
        viewModel.toggleSelection(RemotePath(raw: "/x/a"))
        #expect(viewModel.selection.isEmpty)
    }
}
