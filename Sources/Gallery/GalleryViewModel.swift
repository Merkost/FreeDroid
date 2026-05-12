import Foundation
import Observation
import FreeDroidDomain

@MainActor
@Observable
public final class GalleryViewModel {
    public private(set) var sections: [MediaSection] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = false
    public private(set) var lastError: TransportError?
    public var selection: Set<String> = []

    public let folder: RemotePath
    public let loadThumbnail: LoadThumbnailUseCase

    private let loadMediaUseCase: LoadMediaUseCase
    private let grouper: MediaGrouper
    private var nextPage = 0
    private var rawItems: [MediaItem] = []

    public init(
        folder: RemotePath,
        loadMedia: LoadMediaUseCase,
        loadThumbnail: LoadThumbnailUseCase,
        grouper: MediaGrouper = MediaGrouper()
    ) {
        self.folder = folder
        self.loadMediaUseCase = loadMedia
        self.loadThumbnail = loadThumbnail
        self.grouper = grouper
    }

    public func load() async {
        rawItems = []
        nextPage = 0
        sections = []
        await loadMore()
    }

    public func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await loadMediaUseCase(folder: folder, page: nextPage)
            rawItems.append(contentsOf: page.items)
            sections = grouper.group(rawItems)
            hasMore = page.hasMore
            nextPage = page.nextPage ?? nextPage
            lastError = nil
        } catch let error as TransportError {
            lastError = error
        } catch {
            lastError = .ioFailure(message: String(describing: error))
        }
    }

    public func toggleSelection(_ item: MediaItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    public func clearSelection() {
        selection.removeAll()
    }

    public var selectedItems: [MediaItem] {
        rawItems.filter { selection.contains($0.id) }
    }
}
