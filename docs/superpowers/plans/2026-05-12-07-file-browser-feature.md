# FreeDroid Plan #7 — File Browser Feature

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `FileBrowser` feature: a two-pane browser (sidebar + content) for the currently-selected device. Shows a breadcrumb, directory listing with sorting, file selection, context menu actions (rename/delete/new folder), and integrates the `CommandStrip` for bulk actions.

**Architecture:** Feature package depending on Domain + UI. `@Observable` `FileBrowserViewModel` holds current path, entries, sort, and selection. Backed by injected `FileRepository`. Drag-and-drop via SwiftUI's `.onDrop`.

**Tech Stack:** SwiftUI, FreeDroidDomain, FreeDroidUI.

---

## File Structure

```
Packages/Features/FileBrowser/
├── Package.swift                                       create
├── Sources/FileBrowser/
│   ├── FileBrowserViewModel.swift                      @Observable
│   ├── FileBrowserView.swift                           main view
│   ├── BreadcrumbBar.swift
│   ├── FileRowView.swift
│   ├── FileBrowserSelection.swift                      value
│   ├── FileSortOption.swift                            enum
│   ├── BrowseFolderUseCase.swift                       use case
│   ├── RenameFileUseCase.swift                         use case
│   ├── DeleteFilesUseCase.swift                        use case
│   ├── CreateFolderUseCase.swift                       use case
│   └── FileIconResolver.swift                          maps extensions to SF Symbols
└── Tests/FileBrowserTests/
    ├── FileBrowserViewModelTests.swift
    ├── FileSortOptionTests.swift
    └── FileIconResolverTests.swift
```

---

## Task 1: Package skeleton

**Files:**
- Create: `Packages/Features/FileBrowser/Package.swift`

- [ ] **Step 1: Write the manifest**

Write `Packages/Features/FileBrowser/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileBrowser",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FileBrowser", targets: ["FileBrowser"])
    ],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "FileBrowser",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FileBrowserTests",
            dependencies: ["FileBrowser"],
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
mkdir -p Packages/Features/FileBrowser/Sources/FileBrowser
mkdir -p Packages/Features/FileBrowser/Tests/FileBrowserTests
touch Packages/Features/FileBrowser/Sources/FileBrowser/.gitkeep
cd Packages/Features/FileBrowser && swift build && cd ../../..
```

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): scaffold FileBrowser feature package"
```

---

## Task 2: `FileSortOption` with tests

**Files:**
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/FileSortOption.swift`
- Create: `Packages/Features/FileBrowser/Tests/FileBrowserTests/FileSortOptionTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/Features/FileBrowser/Tests/FileBrowserTests/FileSortOptionTests.swift`:

```swift
import Foundation
import Testing
import FreeDroidDomain
@testable import FileBrowser

@Suite("FileSortOption")
struct FileSortOptionTests {
    private func entry(_ name: String, size: Int64? = nil, kind: EntryKind = .file, mtime: Date? = nil) -> RemoteEntry {
        RemoteEntry(
            path: RemotePath(raw: "/x/\(name)"),
            name: name,
            kind: kind,
            sizeBytes: size,
            modifiedAt: mtime,
            isHidden: false
        )
    }

    @Test func nameAscendingFoldersFirst() {
        let entries = [entry("zebra.txt"), entry("apple", kind: .directory), entry("banana.txt")]
        let sorted = FileSortOption.name.apply(entries, ascending: true)
        #expect(sorted.map(\.name) == ["apple", "banana.txt", "zebra.txt"])
    }

    @Test func sizeDescending() {
        let entries = [entry("small", size: 100), entry("big", size: 1000), entry("med", size: 500)]
        let sorted = FileSortOption.size.apply(entries, ascending: false)
        #expect(sorted.map(\.name) == ["big", "med", "small"])
    }

    @Test func modifiedDescending() {
        let now = Date()
        let entries = [
            entry("old", mtime: now.addingTimeInterval(-3600)),
            entry("new", mtime: now),
            entry("mid", mtime: now.addingTimeInterval(-1800))
        ]
        let sorted = FileSortOption.modified.apply(entries, ascending: false)
        #expect(sorted.map(\.name) == ["new", "mid", "old"])
    }
}
```

- [ ] **Step 2: Implement `FileSortOption`**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/FileSortOption.swift`:

```swift
import Foundation
import FreeDroidDomain

public enum FileSortOption: String, CaseIterable, Sendable {
    case name, size, modified, kind

    public func apply(_ entries: [RemoteEntry], ascending: Bool) -> [RemoteEntry] {
        let dirs = entries.filter { $0.kind == .directory }
        let files = entries.filter { $0.kind != .directory }
        let sortedDirs = dirs.sorted(by: comparator(ascending: ascending))
        let sortedFiles = files.sorted(by: comparator(ascending: ascending))
        return sortedDirs + sortedFiles
    }

    private func comparator(ascending: Bool) -> (RemoteEntry, RemoteEntry) -> Bool {
        switch self {
        case .name:
            return { lhs, rhs in
                let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        case .size:
            return { lhs, rhs in
                let l = lhs.sizeBytes ?? 0
                let r = rhs.sizeBytes ?? 0
                return ascending ? l < r : l > r
            }
        case .modified:
            return { lhs, rhs in
                let l = lhs.modifiedAt ?? .distantPast
                let r = rhs.modifiedAt ?? .distantPast
                return ascending ? l < r : l > r
            }
        case .kind:
            return { lhs, rhs in
                let l = lhs.name.split(separator: ".").last.map(String.init) ?? ""
                let r = rhs.name.split(separator: ".").last.map(String.init) ?? ""
                let cmp = l.localizedCaseInsensitiveCompare(r)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/Features/FileBrowser && swift test --filter FileSortOptionTests`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): add FileSortOption with tests"
```

---

## Task 3: `FileIconResolver` with tests

**Files:**
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/FileIconResolver.swift`
- Create: `Packages/Features/FileBrowser/Tests/FileBrowserTests/FileIconResolverTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/Features/FileBrowser/Tests/FileBrowserTests/FileIconResolverTests.swift`:

```swift
import Testing
import FreeDroidDomain
@testable import FileBrowser

@Suite("FileIconResolver")
struct FileIconResolverTests {
    @Test func directoryIcon() {
        let entry = RemoteEntry(path: RemotePath(raw: "/x/DCIM"), name: "DCIM", kind: .directory, sizeBytes: nil, modifiedAt: nil, isHidden: false)
        #expect(FileIconResolver.symbol(for: entry) == "folder")
    }

    @Test func imageIcon() {
        let entry = RemoteEntry(path: RemotePath(raw: "/x/a.jpg"), name: "a.jpg", kind: .file, sizeBytes: 1, modifiedAt: nil, isHidden: false)
        #expect(FileIconResolver.symbol(for: entry) == "photo")
    }

    @Test func videoIcon() {
        let entry = RemoteEntry(path: RemotePath(raw: "/x/a.mp4"), name: "a.mp4", kind: .file, sizeBytes: 1, modifiedAt: nil, isHidden: false)
        #expect(FileIconResolver.symbol(for: entry) == "play.rectangle")
    }

    @Test func documentIcon() {
        let entry = RemoteEntry(path: RemotePath(raw: "/x/a.pdf"), name: "a.pdf", kind: .file, sizeBytes: 1, modifiedAt: nil, isHidden: false)
        #expect(FileIconResolver.symbol(for: entry) == "doc.richtext")
    }

    @Test func defaultIcon() {
        let entry = RemoteEntry(path: RemotePath(raw: "/x/a.weird"), name: "a.weird", kind: .file, sizeBytes: 1, modifiedAt: nil, isHidden: false)
        #expect(FileIconResolver.symbol(for: entry) == "doc")
    }
}
```

- [ ] **Step 2: Implement resolver**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/FileIconResolver.swift`:

```swift
import FreeDroidDomain

public enum FileIconResolver {
    public static func symbol(for entry: RemoteEntry) -> String {
        if entry.kind == .directory { return "folder" }
        let lower = entry.name.lowercased()
        if let dot = lower.lastIndex(of: ".") {
            let ext = String(lower[lower.index(after: dot)...])
            return symbol(forExtension: ext)
        }
        return "doc"
    }

    private static func symbol(forExtension ext: String) -> String {
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "bmp", "tiff": "photo"
        case "mp4", "mov", "m4v", "webm", "mkv", "avi": "play.rectangle"
        case "mp3", "m4a", "wav", "flac", "ogg": "music.note"
        case "pdf", "txt", "rtf", "doc", "docx", "md": "doc.richtext"
        case "zip", "tar", "gz", "7z", "rar": "archivebox"
        case "apk": "shippingbox"
        default: "doc"
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/Features/FileBrowser && swift test --filter FileIconResolverTests`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): add FileIconResolver with tests"
```

---

## Task 4: Use case protocols

**Files:**
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/BrowseFolderUseCase.swift`
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/RenameFileUseCase.swift`
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/DeleteFilesUseCase.swift`
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/CreateFolderUseCase.swift`

- [ ] **Step 1: Implement use cases**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/BrowseFolderUseCase.swift`:

```swift
import FreeDroidDomain

public struct BrowseFolderUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(_ path: RemotePath) async throws -> [RemoteEntry] {
        try await fileRepository.list(path)
    }
}
```

Write `Packages/Features/FileBrowser/Sources/FileBrowser/RenameFileUseCase.swift`:

```swift
import FreeDroidDomain

public struct RenameFileUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(from: RemotePath, to dest: RemotePath) async throws {
        try await fileRepository.rename(from, to: dest)
    }
}
```

Write `Packages/Features/FileBrowser/Sources/FileBrowser/DeleteFilesUseCase.swift`:

```swift
import FreeDroidDomain

public struct DeleteFilesUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(paths: [RemotePath]) async throws {
        for path in paths {
            try await fileRepository.remove(path)
        }
    }
}
```

Write `Packages/Features/FileBrowser/Sources/FileBrowser/CreateFolderUseCase.swift`:

```swift
import FreeDroidDomain

public struct CreateFolderUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(at parent: RemotePath, name: String) async throws -> RemotePath {
        let target = parent.appending(name)
        try await fileRepository.mkdir(target)
        return target
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/FileBrowser && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): add Browse, Rename, Delete, CreateFolder use cases"
```

---

## Task 5: `FileBrowserViewModel` with tests

**Files:**
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/FileBrowserSelection.swift`
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/FileBrowserViewModel.swift`
- Create: `Packages/Features/FileBrowser/Tests/FileBrowserTests/FileBrowserViewModelTests.swift`

- [ ] **Step 1: Implement `FileBrowserSelection`**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/FileBrowserSelection.swift`:

```swift
import FreeDroidDomain

public struct FileBrowserSelection: Equatable, Sendable {
    public private(set) var paths: Set<RemotePath>

    public init(paths: Set<RemotePath> = []) {
        self.paths = paths
    }

    public var count: Int { paths.count }
    public var isEmpty: Bool { paths.isEmpty }

    public mutating func toggle(_ path: RemotePath) {
        if paths.contains(path) {
            paths.remove(path)
        } else {
            paths.insert(path)
        }
    }

    public mutating func replace(with path: RemotePath) {
        paths = [path]
    }

    public mutating func clear() {
        paths.removeAll()
    }

    public func contains(_ path: RemotePath) -> Bool {
        paths.contains(path)
    }
}
```

- [ ] **Step 2: Write failing tests**

Write `Packages/Features/FileBrowser/Tests/FileBrowserTests/FileBrowserViewModelTests.swift`:

```swift
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
        entries[parent, default: []].append(RemoteEntry(path: path, name: path.name, kind: .directory, sizeBytes: nil, modifiedAt: nil, isHidden: false))
    }
    func remove(_ path: RemotePath) async throws {
        let parent = path.parent ?? .root
        entries[parent]?.removeAll { $0.path == path }
    }
    func rename(_ from: RemotePath, to dest: RemotePath) async throws {}

    func seed(_ path: RemotePath, _ items: [RemoteEntry]) async {
        entries[path] = items
    }
}

@MainActor
@Suite("FileBrowserViewModel")
struct FileBrowserViewModelTests {
    private func entry(_ name: String, kind: EntryKind = .file) -> RemoteEntry {
        RemoteEntry(path: RemotePath(raw: "/sdcard/\(name)"), name: name, kind: kind, sizeBytes: 100, modifiedAt: nil, isHidden: false)
    }

    @Test func loadFolderPopulatesEntries() async throws {
        let repo = StubFileRepository()
        await repo.seed(RemotePath(raw: "/sdcard"), [entry("DCIM", kind: .directory), entry("photo.jpg")])
        let vm = FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: repo),
            renameFile: RenameFileUseCase(fileRepository: repo),
            deleteFiles: DeleteFilesUseCase(fileRepository: repo),
            createFolder: CreateFolderUseCase(fileRepository: repo)
        )
        await vm.navigate(to: RemotePath(raw: "/sdcard"))
        #expect(vm.entries.count == 2)
        #expect(vm.entries.first?.kind == .directory)
    }

    @Test func navigateUpdatesBreadcrumb() async {
        let repo = StubFileRepository()
        await repo.seed(RemotePath(raw: "/sdcard/DCIM"), [])
        let vm = FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: repo),
            renameFile: RenameFileUseCase(fileRepository: repo),
            deleteFiles: DeleteFilesUseCase(fileRepository: repo),
            createFolder: CreateFolderUseCase(fileRepository: repo)
        )
        await vm.navigate(to: RemotePath(raw: "/sdcard/DCIM"))
        #expect(vm.breadcrumb == ["sdcard", "DCIM"])
    }

    @Test func toggleSelection() async {
        let repo = StubFileRepository()
        await repo.seed(RemotePath(raw: "/x"), [entry("a"), entry("b")])
        let vm = FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: repo),
            renameFile: RenameFileUseCase(fileRepository: repo),
            deleteFiles: DeleteFilesUseCase(fileRepository: repo),
            createFolder: CreateFolderUseCase(fileRepository: repo)
        )
        await vm.navigate(to: RemotePath(raw: "/x"))
        vm.toggleSelection(RemotePath(raw: "/x/a"))
        #expect(vm.selection.count == 1)
        vm.toggleSelection(RemotePath(raw: "/x/a"))
        #expect(vm.selection.isEmpty)
    }
}
```

- [ ] **Step 3: Implement `FileBrowserViewModel`**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/FileBrowserViewModel.swift`:

```swift
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

    private let browseFolder: BrowseFolderUseCase
    private let renameFile: RenameFileUseCase
    private let deleteFiles: DeleteFilesUseCase
    private let createFolder: CreateFolderUseCase

    public init(
        browseFolder: BrowseFolderUseCase,
        renameFile: RenameFileUseCase,
        deleteFiles: DeleteFilesUseCase,
        createFolder: CreateFolderUseCase
    ) {
        self.browseFolder = browseFolder
        self.renameFile = renameFile
        self.deleteFiles = deleteFiles
        self.createFolder = createFolder
    }

    public var breadcrumb: [String] {
        let components = path.raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return components
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
            let raw = try await browseFolder(path)
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

    public func toggleSelection(_ path: RemotePath) {
        selection.toggle(path)
    }

    public func selectOnly(_ path: RemotePath) {
        selection.replace(with: path)
    }

    public func clearSelection() {
        selection.clear()
    }

    public func deleteSelection() async {
        guard !selection.isEmpty else { return }
        do {
            try await deleteFiles(paths: Array(selection.paths))
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
            _ = try await createFolder(at: path, name: name)
            await reload()
        } catch let error as TransportError {
            lastError = error
        } catch {
            lastError = .ioFailure(message: String(describing: error))
        }
    }

    public func rename(_ path: RemotePath, to newName: String) async {
        let parent = path.parent ?? .root
        let dest = parent.appending(newName)
        do {
            try await renameFile(from: path, to: dest)
            await reload()
        } catch let error as TransportError {
            lastError = error
        } catch {
            lastError = .ioFailure(message: String(describing: error))
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/Features/FileBrowser && swift test --filter FileBrowserViewModelTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): add FileBrowserViewModel with tests"
```

---

## Task 6: `BreadcrumbBar` view

**Files:**
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/BreadcrumbBar.swift`

- [ ] **Step 1: Implement `BreadcrumbBar`**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/BreadcrumbBar.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct BreadcrumbBar: View {
    @Environment(\.theme) private var theme
    private let components: [String]
    private let onSelect: (RemotePath) -> Void

    public init(components: [String], onSelect: @escaping (RemotePath) -> Void) {
        self.components = components
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            crumb(label: "/", path: .root)
            ForEach(Array(components.enumerated()), id: \.offset) { idx, name in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.colors.text3)
                let path = RemotePath(raw: "/" + components[0...idx].joined(separator: "/"))
                crumb(label: name, path: path, isCurrent: idx == components.count - 1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func crumb(label: String, path: RemotePath, isCurrent: Bool = false) -> some View {
        Button {
            onSelect(path)
        } label: {
            Text(label)
                .font(Typography.callout)
                .foregroundStyle(isCurrent ? theme.colors.text0 : theme.colors.text1)
                .fontWeight(isCurrent ? .medium : .regular)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isCurrent ? theme.colors.line : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/FileBrowser && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): add BreadcrumbBar"
```

---

## Task 7: `FileRowView`

**Files:**
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/FileRowView.swift`

- [ ] **Step 1: Implement the row**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/FileRowView.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct FileRowView: View {
    @Environment(\.theme) private var theme
    public let entry: RemoteEntry
    public let isSelected: Bool

    public init(entry: RemoteEntry, isSelected: Bool) {
        self.entry = entry
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: Spacing.md - 2) {
            Image(systemName: FileIconResolver.symbol(for: entry))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.text1)
                .frame(width: 20)
            Text(entry.name)
                .font(Typography.body)
                .foregroundStyle(theme.colors.text0)
                .lineLimit(1)
            Spacer()
            if entry.kind != .directory, let size = entry.sizeBytes {
                Text(ByteCountFormatter().string(fromByteCount: size))
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
                    .frame(width: 100, alignment: .trailing)
            } else {
                Text("—")
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text3)
                    .frame(width: 100, alignment: .trailing)
            }
            if let mtime = entry.modifiedAt {
                Text(mtime.formatted(.dateTime.month().day().year(.twoDigits).hour().minute()))
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
                    .frame(width: 130, alignment: .trailing)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs + 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isSelected ? theme.colors.accentSoft : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(isSelected ? theme.colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/FileBrowser && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): add FileRowView"
```

---

## Task 8: `FileBrowserView`

**Files:**
- Create: `Packages/Features/FileBrowser/Sources/FileBrowser/FileBrowserView.swift`

- [ ] **Step 1: Implement the main view**

Write `Packages/Features/FileBrowser/Sources/FileBrowser/FileBrowserView.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct FileBrowserView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: FileBrowserViewModel
    @State private var renameTarget: RemoteEntry?
    @State private var newName: String = ""
    @State private var isCreatingFolder = false
    @State private var newFolderName: String = ""

    public init(viewModel: FileBrowserViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                BreadcrumbBar(components: viewModel.breadcrumb) { path in
                    Task { await viewModel.navigate(to: path) }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)

                Divider().overlay(theme.colors.line)

                if viewModel.isLoading && viewModel.entries.isEmpty {
                    VStack { Spacer(); Spinner(size: 24); Spacer() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.entries.isEmpty {
                    EmptyState(
                        icon: "folder",
                        title: "Empty folder",
                        message: "Nothing here yet. Drag files in to upload.",
                        actionLabel: "New folder"
                    ) {
                        isCreatingFolder = true
                    }
                } else {
                    list
                }
            }

            if !viewModel.selection.isEmpty {
                CommandStrip(
                    selectionCount: viewModel.selection.count,
                    actions: [
                        CommandStripAction(label: "Delete", systemImage: "trash") {
                            Task { await viewModel.deleteSelection() }
                        },
                        CommandStripAction(label: "Clear", systemImage: "xmark.circle") {
                            viewModel.clearSelection()
                        }
                    ]
                )
                .padding(.bottom, Spacing.lg)
            }
        }
        .task { await viewModel.reload() }
        .sheet(item: $renameTarget) { entry in
            renameSheet(for: entry)
        }
        .sheet(isPresented: $isCreatingFolder) {
            newFolderSheet
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.entries) { entry in
                    FileRowView(entry: entry, isSelected: viewModel.selection.contains(entry.path))
                        .onTapGesture {
                            if entry.kind == .directory {
                                Task { await viewModel.navigate(to: entry.path) }
                            } else {
                                viewModel.toggleSelection(entry.path)
                            }
                        }
                        .contextMenu {
                            Button("Rename") {
                                renameTarget = entry
                                newName = entry.name
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.selectOnly(entry.path)
                                Task { await viewModel.deleteSelection() }
                            }
                        }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func renameSheet(for entry: RemoteEntry) -> some View {
        Sheet {
            Text("Rename").font(Typography.title)
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { renameTarget = nil }
                Button("Rename") {
                    let target = entry
                    Task { await viewModel.rename(target.path, to: newName); renameTarget = nil }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
                .disabled(newName.isEmpty)
            }
        }
        .padding()
    }

    private var newFolderSheet: some View {
        Sheet {
            Text("New folder").font(Typography.title)
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { isCreatingFolder = false; newFolderName = "" }
                Button("Create") {
                    let name = newFolderName
                    Task { await viewModel.createFolder(named: name); isCreatingFolder = false; newFolderName = "" }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
                .disabled(newFolderName.isEmpty)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/FileBrowser && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/FileBrowser
git commit -m "feat(browser): add FileBrowserView with rename and create-folder sheets"
```

---

## Task 9: Wire into app

**Files:**
- Modify: `FreeDroid/AppContainer.swift`
- Modify: `FreeDroid/ContentView.swift`

- [ ] **Step 1: Add package to workspace**

Xcode → Add Package Dependencies → Add Local → `Packages/Features/FileBrowser`. Add to target frameworks.

- [ ] **Step 2: Extend `AppContainer`**

In `FreeDroid/AppContainer.swift`, add after `deviceRepository`:

```swift
import FileBrowser
```

```swift
    func fileBrowserViewModel(for deviceID: DeviceID) -> FileBrowserViewModel {
        let fileRepo = FileRepositoryImpl(registry: registry, cache: listingCache, deviceID: deviceID)
        return FileBrowserViewModel(
            browseFolder: BrowseFolderUseCase(fileRepository: fileRepo),
            renameFile: RenameFileUseCase(fileRepository: fileRepo),
            deleteFiles: DeleteFilesUseCase(fileRepository: fileRepo),
            createFolder: CreateFolderUseCase(fileRepository: fileRepo)
        )
    }
```

- [ ] **Step 3: Update `ContentView` to host the browser**

In `FreeDroid/ContentView.swift`, replace `placeholderDetail` body:

```swift
    @ViewBuilder
    private var detail: some View {
        if let selectedID = container.deviceListViewModel.selectedID {
            let vm = container.fileBrowserViewModel(for: selectedID)
            FileBrowserView(viewModel: vm)
                .id(selectedID)
        } else {
            placeholderDetail
        }
    }
```

Replace the `HStack` body to use `detail` instead of `placeholderDetail`.

Add `import FileBrowser` at the top.

- [ ] **Step 4: Build and run**

`⌘R` in Xcode. With a device authorized, selecting it in the sidebar shows the file browser at `/`. Navigate into folders by clicking.

- [ ] **Step 5: Commit**

```bash
git add FreeDroid Packages/Features/FileBrowser
git commit -m "feat: wire FileBrowser into app with per-device view model"
```

---

## Task 10: CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add `test-browser` job**

```yaml
  test-browser:
    name: Test FileBrowser
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'
      - run: cd Packages/Features/FileBrowser && swift test --parallel
```

Add to `build-app.needs`.

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "ci: run FileBrowser test suite"
```

---

## Done When

- `swift test` in `FileBrowser` passes.
- The app shows the file browser for the selected device.
- Navigation, sort, rename, delete, and new folder all work end-to-end against a real device.
- Selecting files shows a Command Strip at the bottom with "Delete" and "Clear".
- SwiftLint passes.

## Self-Review

- Spec §6 (Repository abstractions) → use cases in Task 4.
- Spec §8 (Glass over Grain + components) → `BreadcrumbBar`, `FileRowView`, `CommandStrip` integration.
- Spec §4 (Clean Architecture) → View → ViewModel → UseCase → Repository chain, dependency direction inward.
