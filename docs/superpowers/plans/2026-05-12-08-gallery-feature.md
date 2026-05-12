# FreeDroid Plan #8 — Gallery Feature

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `Gallery` feature: spatial masonry photo grid with date-grouped sections, thumbnail loading via `MediaRepository`, hover parallax, selection rings, Quick Look preview integration, and a Command Strip for "Copy to Mac".

**Architecture:** Feature package depending only on Domain + UI. `GalleryViewModel` (`@Observable`) drives the grid and selection. `MediaGrouper` (pure) sections items by capture date. `AsyncThumbnail` view wraps thumbnail loading with progressive reveal. Quick Look uses macOS `QLPreviewPanel` via `NSViewRepresentable`.

**Tech Stack:** SwiftUI, FreeDroidDomain, FreeDroidUI, AppKit Quick Look.

---

## File Structure

```
Packages/Features/Gallery/
├── Package.swift                                       create
├── Sources/Gallery/
│   ├── GalleryViewModel.swift                          @Observable
│   ├── GalleryView.swift                               main grid view
│   ├── PhotoTile.swift                                 single tile with parallax
│   ├── AsyncThumbnail.swift                            loading wrapper
│   ├── MediaGrouper.swift                              pure grouping
│   ├── MediaSection.swift                              value type
│   ├── LoadMediaUseCase.swift
│   ├── LoadThumbnailUseCase.swift
│   ├── QuickLookPresenter.swift                        NSViewRepresentable
│   └── GalleryDateFormatter.swift                      pure helper
└── Tests/GalleryTests/
    ├── GalleryViewModelTests.swift
    ├── MediaGrouperTests.swift
    └── GalleryDateFormatterTests.swift
```

---

## Task 1: Package skeleton

**Files:**
- Create: `Packages/Features/Gallery/Package.swift`

- [ ] **Step 1: Write manifest**

Write `Packages/Features/Gallery/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gallery",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Gallery", targets: ["Gallery"])
    ],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "Gallery",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GalleryTests",
            dependencies: ["Gallery"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
```

- [ ] **Step 2: Create directories and build**

```bash
mkdir -p Packages/Features/Gallery/Sources/Gallery
mkdir -p Packages/Features/Gallery/Tests/GalleryTests
touch Packages/Features/Gallery/Sources/Gallery/.gitkeep
cd Packages/Features/Gallery && swift build && cd ../../..
```

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): scaffold Gallery feature package"
```

---

## Task 2: `GalleryDateFormatter` + `MediaSection` + `MediaGrouper`

**Files:**
- Create: `Packages/Features/Gallery/Sources/Gallery/GalleryDateFormatter.swift`
- Create: `Packages/Features/Gallery/Sources/Gallery/MediaSection.swift`
- Create: `Packages/Features/Gallery/Sources/Gallery/MediaGrouper.swift`
- Create: `Packages/Features/Gallery/Tests/GalleryTests/GalleryDateFormatterTests.swift`
- Create: `Packages/Features/Gallery/Tests/GalleryTests/MediaGrouperTests.swift`

- [ ] **Step 1: Write failing date formatter tests**

Write `Packages/Features/Gallery/Tests/GalleryTests/GalleryDateFormatterTests.swift`:

```swift
import Foundation
import Testing
@testable import Gallery

@Suite("GalleryDateFormatter")
struct GalleryDateFormatterTests {
    @Test func todayLabel() {
        let formatter = GalleryDateFormatter(calendar: Calendar(identifier: .gregorian), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(formatter.label(for: today) == "Today")
    }

    @Test func yesterdayLabel() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let formatter = GalleryDateFormatter(calendar: calendar, now: { now })
        #expect(formatter.label(for: yesterday) == "Yesterday")
    }
}
```

- [ ] **Step 2: Implement `GalleryDateFormatter`**

Write `Packages/Features/Gallery/Sources/Gallery/GalleryDateFormatter.swift`:

```swift
import Foundation

public struct GalleryDateFormatter: Sendable {
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    public func label(for date: Date) -> String {
        let today = now()
        if calendar.isDate(date, inSameDayAs: today) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let daysAgo = calendar.dateComponents([.day], from: date, to: today).day ?? 0
        if daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
```

- [ ] **Step 3: Implement `MediaSection` and `MediaGrouper`**

Write `Packages/Features/Gallery/Sources/Gallery/MediaSection.swift`:

```swift
import Foundation
import FreeDroidDomain

public struct MediaSection: Identifiable, Sendable, Hashable {
    public let id: Date
    public let label: String
    public let items: [MediaItem]
}
```

Write `Packages/Features/Gallery/Sources/Gallery/MediaGrouper.swift`:

```swift
import Foundation
import FreeDroidDomain

public struct MediaGrouper: Sendable {
    private let formatter: GalleryDateFormatter

    public init(formatter: GalleryDateFormatter = GalleryDateFormatter()) {
        self.formatter = formatter
    }

    public func group(_ items: [MediaItem]) -> [MediaSection] {
        let withDate = items.compactMap { item -> (Date, MediaItem)? in
            guard let date = item.captureDate else { return nil }
            return (formatter.startOfDay(for: date), item)
        }
        let grouped = Dictionary(grouping: withDate, by: \.0)
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let groupItems = grouped[key]?.map(\.1) ?? []
            return MediaSection(id: key, label: formatter.label(for: key), items: groupItems)
        }
    }
}
```

- [ ] **Step 4: Write grouper test**

Write `Packages/Features/Gallery/Tests/GalleryTests/MediaGrouperTests.swift`:

```swift
import Foundation
import Testing
import FreeDroidDomain
@testable import Gallery

@Suite("MediaGrouper")
struct MediaGrouperTests {
    @Test func groupsByDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let items = [
            item(now, name: "a"),
            item(now.addingTimeInterval(3600), name: "b"),
            item(yesterday, name: "c")
        ]
        let formatter = GalleryDateFormatter(calendar: calendar, now: { now })
        let grouper = MediaGrouper(formatter: formatter)
        let sections = grouper.group(items)
        #expect(sections.count == 2)
        #expect(sections[0].label == "Today")
        #expect(sections[0].items.count == 2)
        #expect(sections[1].label == "Yesterday")
    }

    private func item(_ date: Date, name: String) -> MediaItem {
        MediaItem(
            id: name,
            path: RemotePath(raw: "/x/\(name)"),
            kind: .image,
            captureDate: date,
            sizeBytes: 100
        )
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd Packages/Features/Gallery && swift test --filter MediaGrouperTests`
Run: `cd Packages/Features/Gallery && swift test --filter GalleryDateFormatterTests`
Expected: both suites pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): add MediaGrouper and GalleryDateFormatter"
```

---

## Task 3: Use cases

**Files:**
- Create: `Packages/Features/Gallery/Sources/Gallery/LoadMediaUseCase.swift`
- Create: `Packages/Features/Gallery/Sources/Gallery/LoadThumbnailUseCase.swift`

- [ ] **Step 1: Implement `LoadMediaUseCase`**

Write `Packages/Features/Gallery/Sources/Gallery/LoadMediaUseCase.swift`:

```swift
import FreeDroidDomain

public struct LoadMediaUseCase: Sendable {
    public let mediaRepository: any MediaRepository

    public init(mediaRepository: any MediaRepository) {
        self.mediaRepository = mediaRepository
    }

    public func callAsFunction(folder: RemotePath, page: Int = 0) async throws -> MediaPage {
        try await mediaRepository.listMedia(in: folder, page: page)
    }
}
```

- [ ] **Step 2: Implement `LoadThumbnailUseCase`**

Write `Packages/Features/Gallery/Sources/Gallery/LoadThumbnailUseCase.swift`:

```swift
import Foundation
import FreeDroidDomain

public struct LoadThumbnailUseCase: Sendable {
    public let mediaRepository: any MediaRepository

    public init(mediaRepository: any MediaRepository) {
        self.mediaRepository = mediaRepository
    }

    public func callAsFunction(for item: MediaItem, size: ThumbnailSize = .medium) async throws -> Data {
        try await mediaRepository.thumbnail(for: item, size: size)
    }
}
```

- [ ] **Step 3: Build and commit**

Run: `cd Packages/Features/Gallery && swift build`

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): add Load{Media,Thumbnail}UseCase"
```

---

## Task 4: `GalleryViewModel` with tests

**Files:**
- Create: `Packages/Features/Gallery/Sources/Gallery/GalleryViewModel.swift`
- Create: `Packages/Features/Gallery/Tests/GalleryTests/GalleryViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/Features/Gallery/Tests/GalleryTests/GalleryViewModelTests.swift`:

```swift
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
        MediaItem(id: name, path: RemotePath(raw: "/x/\(name)"), kind: .image, captureDate: date, sizeBytes: 1)
    }

    @Test func loadingInsertsSectionsAndItems() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = StubMediaRepository(pages: [
            0: MediaPage(items: [mediaItem("a", date: now), mediaItem("b", date: now)], hasMore: false, nextPage: nil)
        ])
        let vm = GalleryViewModel(
            folder: RemotePath(raw: "/DCIM/Camera"),
            loadMedia: LoadMediaUseCase(mediaRepository: repo),
            loadThumbnail: LoadThumbnailUseCase(mediaRepository: repo),
            grouper: MediaGrouper(formatter: GalleryDateFormatter(calendar: Calendar(identifier: .gregorian), now: { now }))
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
```

- [ ] **Step 2: Implement `GalleryViewModel`**

Write `Packages/Features/Gallery/Sources/Gallery/GalleryViewModel.swift`:

```swift
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

    private let loadMedia: LoadMediaUseCase
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
        self.loadMedia = loadMedia
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
            let page = try await loadMedia(folder: folder, page: nextPage)
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
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/Features/Gallery && swift test --filter GalleryViewModelTests`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): add GalleryViewModel with paging and selection"
```

---

## Task 5: `AsyncThumbnail` view

**Files:**
- Create: `Packages/Features/Gallery/Sources/Gallery/AsyncThumbnail.swift`

- [ ] **Step 1: Implement the view**

Write `Packages/Features/Gallery/Sources/Gallery/AsyncThumbnail.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct AsyncThumbnail: View {
    @Environment(\.theme) private var theme
    private let item: MediaItem
    private let loader: LoadThumbnailUseCase
    private let size: ThumbnailSize

    @State private var image: NSImage?
    @State private var hasFailed = false

    public init(item: MediaItem, loader: LoadThumbnailUseCase, size: ThumbnailSize = .medium) {
        self.item = item
        self.loader = loader
        self.size = size
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else if hasFailed {
                ZStack {
                    Rectangle().fill(theme.colors.background2)
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(theme.colors.text2)
                }
            } else {
                ZStack {
                    Rectangle().fill(theme.colors.background2)
                    Spinner(size: 14)
                }
            }
        }
        .clipped()
        .motion(.smooth, value: image)
        .task(id: item.id) {
            await loadImage()
        }
    }

    private func loadImage() async {
        do {
            let data = try await loader(for: item, size: size)
            if let nsImage = NSImage(data: data) {
                image = nsImage
            } else {
                hasFailed = true
            }
        } catch {
            hasFailed = true
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/Gallery && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): add AsyncThumbnail with progressive reveal"
```

---

## Task 6: `PhotoTile` with parallax

**Files:**
- Create: `Packages/Features/Gallery/Sources/Gallery/PhotoTile.swift`

- [ ] **Step 1: Implement `PhotoTile`**

Write `Packages/Features/Gallery/Sources/Gallery/PhotoTile.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct PhotoTile: View {
    @Environment(\.theme) private var theme
    private let item: MediaItem
    private let isSelected: Bool
    private let loader: LoadThumbnailUseCase
    private let onTap: () -> Void

    @State private var isHovered = false
    @State private var hoverOffset: CGSize = .zero

    public init(item: MediaItem, isSelected: Bool, loader: LoadThumbnailUseCase, onTap: @escaping () -> Void) {
        self.item = item
        self.isSelected = isSelected
        self.loader = loader
        self.onTap = onTap
    }

    public var body: some View {
        let height = CGFloat(120 + (abs(item.id.hashValue) % 80))
        ZStack(alignment: .topLeading) {
            AsyncThumbnail(item: item, loader: loader)
                .frame(height: height)
                .background(theme.colors.background2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(isSelected ? theme.colors.accent : .clear, lineWidth: 2)
                )

            if isHovered || isSelected {
                Circle()
                    .fill(isSelected ? theme.colors.accent : Color.black.opacity(0.45))
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.4)
                    )
                    .frame(width: 18, height: 18)
                    .padding(Spacing.sm)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .offset(hoverOffset)
        .shadow(color: isHovered ? .black.opacity(0.45) : .clear, radius: 18, x: 0, y: 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            isHovered = hovering
            hoverOffset = hovering ? CGSize(width: 0, height: -2) : .zero
        }
        .motion(.smooth, value: isHovered)
        .motion(.smooth, value: isSelected)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/Gallery && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): add PhotoTile with hover parallax and selection ring"
```

---

## Task 7: `QuickLookPresenter`

**Files:**
- Create: `Packages/Features/Gallery/Sources/Gallery/QuickLookPresenter.swift`

- [ ] **Step 1: Implement Quick Look bridge**

Write `Packages/Features/Gallery/Sources/Gallery/QuickLookPresenter.swift`:

```swift
import SwiftUI
import AppKit
import Quartz

public struct QuickLookPresenter: NSViewRepresentable {
    @Binding var url: URL?

    public init(url: Binding<URL?>) {
        self._url = url
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(view: view, urlBinding: $url)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(url: url)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        private var currentURL: URL?
        private var binding: Binding<URL?>?

        func attach(view: NSView, urlBinding: Binding<URL?>) {
            self.binding = urlBinding
        }

        func update(url: URL?) {
            currentURL = url
            guard url != nil else {
                QLPreviewPanel.shared().close()
                return
            }
            let panel = QLPreviewPanel.shared()
            panel?.dataSource = self
            panel?.delegate = self
            panel?.reloadData()
            panel?.makeKeyAndOrderFront(nil)
        }

        public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            currentURL == nil ? 0 : 1
        }

        public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            currentURL as NSURL?
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/Gallery && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): add QuickLookPresenter NSViewRepresentable"
```

---

## Task 8: `GalleryView`

**Files:**
- Create: `Packages/Features/Gallery/Sources/Gallery/GalleryView.swift`

- [ ] **Step 1: Implement the main view**

Write `Packages/Features/Gallery/Sources/Gallery/GalleryView.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct GalleryView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: GalleryViewModel
    var onCopySelectionToMac: ([MediaItem]) -> Void

    public init(viewModel: GalleryViewModel, onCopySelectionToMac: @escaping ([MediaItem]) -> Void) {
        self.viewModel = viewModel
        self.onCopySelectionToMac = onCopySelectionToMac
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    if viewModel.sections.isEmpty && !viewModel.isLoading {
                        EmptyState(
                            icon: "photo.on.rectangle.angled",
                            title: "No photos",
                            message: "Photos and videos from this folder will appear here."
                        )
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(viewModel.sections) { section in
                        section(section)
                    }
                    if viewModel.hasMore {
                        Button("Load more") {
                            Task { await viewModel.loadMore() }
                        }
                        .buttonStyle(.bordered)
                        .padding(.vertical, Spacing.md)
                    }
                }
                .padding(Spacing.lg)
            }
            .task { await viewModel.load() }

            if !viewModel.selection.isEmpty {
                CommandStrip(
                    selectionCount: viewModel.selection.count,
                    actions: [
                        CommandStripAction(label: "Clear", systemImage: "xmark.circle") {
                            viewModel.clearSelection()
                        },
                        CommandStripAction(label: "Copy to Mac", systemImage: "square.and.arrow.down", hotkey: "⌘D", isPrimary: true) {
                            onCopySelectionToMac(viewModel.selectedItems)
                        }
                    ]
                )
                .padding(.bottom, Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private func section(_ section: MediaSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(section.label, detail: "\(section.items.count) items")
            MasonryLayout(columns: 4, spacing: Spacing.md - 2) {
                ForEach(section.items) { item in
                    PhotoTile(
                        item: item,
                        isSelected: viewModel.selection.contains(item.id),
                        loader: viewModel.loadThumbnail
                    ) {
                        viewModel.toggleSelection(item)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/Gallery && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/Gallery
git commit -m "feat(gallery): add GalleryView grid with Command Strip"
```

---

## Task 9: Wire into app

**Files:**
- Modify: `FreeDroid/AppContainer.swift`
- Modify: `FreeDroid/ContentView.swift`

- [ ] **Step 1: Add `Gallery` package to workspace**

Xcode → Add Local → `Packages/Features/Gallery`. Add to target frameworks.

- [ ] **Step 2: Extend `AppContainer`**

In `FreeDroid/AppContainer.swift`, import `Gallery` and add:

```swift
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
```

- [ ] **Step 3: Update `ContentView` to add Gallery tab**

In `FreeDroid/ContentView.swift`, add a `PillTabs` switching between "Files" and "Gallery":

```swift
import Gallery

// inside ContentView body:
@State private var tab: DetailTab = .files

enum DetailTab: Hashable { case files, gallery }
```

In the detail view:

```swift
    @ViewBuilder
    private var detail: some View {
        if let selectedID = container.deviceListViewModel.selectedID {
            VStack(spacing: 0) {
                PillTabs(selection: $tab, tabs: [("Files", DetailTab.files), ("Gallery", DetailTab.gallery)])
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                Divider().overlay(theme.colors.line)
                SidebarFlow(selection: tab) { selectedTab in
                    switch selectedTab {
                    case .files:
                        FileBrowserView(viewModel: container.fileBrowserViewModel(for: selectedID))
                    case .gallery:
                        GalleryView(viewModel: container.galleryViewModel(for: selectedID), onCopySelectionToMac: { items in
                            print("Copy \(items.count) items")
                        })
                    }
                }
            }
            .id(selectedID)
        } else {
            placeholderDetail
        }
    }
```

(The `print` placeholder is replaced in Plan #9 with real transfer integration.)

- [ ] **Step 4: Build and run**

`⌘R`. Switch to Gallery tab — thumbnails should load progressively.

- [ ] **Step 5: Commit**

```bash
git add FreeDroid Packages/Features/Gallery
git commit -m "feat: integrate Gallery feature with Files/Gallery tab switcher"
```

---

## Task 10: CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add `test-gallery` job**

```yaml
  test-gallery:
    name: Test Gallery
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'
      - run: cd Packages/Features/Gallery && swift test --parallel
```

Add to `build-app.needs`.

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "ci: run Gallery test suite"
```

---

## Done When

- `swift test` in `Gallery` passes.
- The Gallery tab renders a masonry grid with thumbnails for `/sdcard/DCIM/Camera` (against a real device).
- Hover gives parallax + lift.
- Multi-select shows the Command Strip with "Copy to Mac" placeholder action.
- SwiftLint passes.

## Self-Review

- Spec §8.3 (Spatial photo grid) → Task 6 (`PhotoTile` with parallax and selection ring).
- Spec §7.4 (`ThumbnailCache`) → consumed in `LoadThumbnailUseCase` via `MediaRepositoryImpl`.
- Spec §4.2 (Clean Architecture) → ViewModel → UseCase → Repository chain.
