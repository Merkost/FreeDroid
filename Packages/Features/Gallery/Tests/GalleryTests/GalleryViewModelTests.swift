import Foundation
import Testing
import FreeDroidDomain
@testable import Gallery

actor StubMediaRepository: MediaRepository {
    let pages: [Int: MediaPage]

    init(pages: [Int: MediaPage]) {
        self.pages = pages
    }

    func listMedia(in folder: RemotePath, page: Int) async throws -> MediaPage {
        pages[page] ?? MediaPage(items: [], hasMore: false, nextPage: nil)
    }

    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> Data {
        Data(repeating: 0xCC, count: 1024)
    }
}

@MainActor
@Suite("GalleryViewModel")
struct GalleryViewModelTests {
    private func mediaItem(_ name: String, date: Date) -> MediaItem {
        MediaItem(
            id: name,
            path: RemotePath(raw: "/x/\(name)"),
            kind: .image,
            captureDate: date,
            sizeBytes: 1
        )
    }

    @Test func loadingInsertsSectionsAndItems() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = StubMediaRepository(pages: [
            0: MediaPage(
                items: [mediaItem("a", date: now), mediaItem("b", date: now)],
                hasMore: false,
                nextPage: nil
            )
        ])
        let vm = GalleryViewModel(
            folder: RemotePath(raw: "/DCIM/Camera"),
            loadMedia: LoadMediaUseCase(mediaRepository: repo),
            loadThumbnail: LoadThumbnailUseCase(mediaRepository: repo),
            grouper: MediaGrouper(
                formatter: GalleryDateFormatter(
                    calendar: Calendar(identifier: .gregorian),
                    now: { now }
                )
            )
        )
        await vm.load()
        #expect(vm.sections.count == 1)
        #expect(vm.sections.first?.items.count == 2)
    }

    @Test func toggleSelectionTracksMultiple() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let vm = GalleryViewModel(
            folder: .root,
            loadMedia: LoadMediaUseCase(mediaRepository: StubMediaRepository(pages: [:])),
            loadThumbnail: LoadThumbnailUseCase(mediaRepository: StubMediaRepository(pages: [:])),
            grouper: MediaGrouper()
        )
        vm.toggleSelection(mediaItem("a", date: now))
        vm.toggleSelection(mediaItem("b", date: now))
        #expect(vm.selection.count == 2)
        vm.toggleSelection(mediaItem("a", date: now))
        #expect(vm.selection.count == 1)
    }
}
