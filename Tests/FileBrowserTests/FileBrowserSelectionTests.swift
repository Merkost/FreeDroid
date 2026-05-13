import Testing
import FreeDroidDomain
@testable import FileBrowser

@MainActor
@Suite("FileBrowserSelection")
struct FileBrowserSelectionTests {
    private func entry(_ name: String, kind: EntryKind = .file) -> RemoteEntry {
        RemoteEntry(
            path: RemotePath(raw: "/x/\(name)"),
            name: name,
            kind: kind,
            sizeBytes: 100,
            modifiedAt: nil,
            isHidden: false
        )
    }

    private func makeViewModel(seeded: [RemoteEntry]) async -> FileBrowserViewModel {
        let repo = StubFileRepository()
        await repo.seed(RemotePath(raw: "/x"), seeded)
        let viewModel = FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: repo),
            renameFile: RenameFileUseCase(fileRepository: repo),
            deleteFiles: DeleteFilesUseCase(fileRepository: repo),
            createFolder: CreateFolderUseCase(fileRepository: repo)
        )
        await viewModel.navigate(to: RemotePath(raw: "/x"))
        return viewModel
    }

    @Test func selectAllSelectsEveryEntry() async {
        let viewModel = await makeViewModel(seeded: [entry("a"), entry("b"), entry("c")])
        viewModel.selectAll()
        #expect(viewModel.selection.count == 3)
    }

    @Test func extendSelectionGrowsRangeFromAnchor() async {
        let viewModel = await makeViewModel(seeded: [entry("a"), entry("b"), entry("c"), entry("d")])
        viewModel.selectOnly(RemotePath(raw: "/x/a"))
        viewModel.extendSelection(to: RemotePath(raw: "/x/c"))
        #expect(viewModel.selection.count == 3)
        #expect(viewModel.selection.contains(RemotePath(raw: "/x/b")))
    }

    @Test func moveFocusWalksEntries() async {
        let viewModel = await makeViewModel(seeded: [entry("a"), entry("b"), entry("c")])
        viewModel.focusFirst()
        viewModel.moveFocus(by: 1)
        #expect(viewModel.focusedPath == RemotePath(raw: "/x/b"))
        viewModel.moveFocus(by: 5)
        #expect(viewModel.focusedPath == RemotePath(raw: "/x/c"))
        viewModel.moveFocus(by: -10)
        #expect(viewModel.focusedPath == RemotePath(raw: "/x/a"))
    }

    @Test func setSortTogglesDirectionOnRepeat() async {
        let viewModel = await makeViewModel(seeded: [entry("a"), entry("b")])
        #expect(viewModel.sort == .name)
        #expect(viewModel.sortAscending == true)
        viewModel.setSort(.name)
        #expect(viewModel.sortAscending == false)
        viewModel.setSort(.size)
        #expect(viewModel.sort == .size)
    }

    @Test func clearSelectionDropsAnchor() async {
        let viewModel = await makeViewModel(seeded: [entry("a"), entry("b")])
        viewModel.selectOnly(RemotePath(raw: "/x/a"))
        viewModel.clearSelection()
        #expect(viewModel.selection.isEmpty)
        #expect(viewModel.selection.anchor == nil)
    }
}
