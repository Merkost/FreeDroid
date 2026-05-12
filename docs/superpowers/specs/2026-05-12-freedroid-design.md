# FreeDroid — Design Spec

**Date:** 2026-05-12
**Status:** Approved (brainstorm phase)
**Author:** Project lead

## 1. Summary

FreeDroid is an open-source macOS application that mounts Android devices as native Finder volumes. It is the free, modern, open-source alternative to MacDroid, focused on quality of execution rather than feature breadth.

**Tagline:** *"Free, fast, feels like Apple made it."*

## 2. Goals & Non-Goals

### Goals (v1.0)

- Mount any Android device as a native macOS volume in Finder
- Support both **ADB** and **MTP** transports over USB, with automatic selection
- Handle multiple devices simultaneously, each as its own volume
- Provide a dedicated **gallery** view for photos and videos with thumbnails and date grouping
- Ship a premium-feeling, distinctive UI with light and dark themes
- Be cleanly open-source-ready from day one: license-clean, contributor-friendly, no proprietary blobs

### Non-Goals (v1.0)

| Excluded | Reason |
|---|---|
| Wi-Fi / wireless ADB | Adds discovery & pairing surface; revisit v0.3+ |
| APK installer | Easy to add later, not core to file management |
| Screen mirroring / scrcpy | Separate problem; separate app |
| Backup / sync scheduling | Not on the path to "browse and transfer" |
| Root filesystem (`/data/data/<pkg>`) | Requires root; niche audience |
| Logcat viewer | Android Studio exists |
| iOS device support | Different protocol stack |
| Mac App Store distribution | FSKit + OSS pricing model — revisit v1.x via FPX strategy |
| Cloud sync | Explicit non-goal |
| Built-in media editing | Finder, Preview, and Photos exist |
| Custom themes beyond light/dark | Possible later via theme tokens |

## 3. Platform & Framework Choices

| Concern | Choice |
|---|---|
| Minimum macOS | **15.4** (Sequoia) — required for FSKit |
| Language | **Swift 6** with strict concurrency enabled |
| UI framework | **SwiftUI** (AppKit interop only where unavoidable) |
| Filesystem extension | **FSKit** (`FSUnaryFileSystem`) |
| Transport implementation | **Hybrid**: bundled `adb` binary for ADB, `libmtp` Swift wrapper for MTP |
| Testing | **Swift Testing** (`@Test`, `#expect`), `swift-snapshot-testing` |
| Updater | **Sparkle 2** with EdDSA-signed appcast (from v0.2) |
| Localization | `Localizable.xcstrings` from v0.1 (English baseline) |

## 4. Architecture

### 4.1 Two-process model

```
┌────────────────────────────────────────────────────────────────┐
│  FreeDroid.app  (main app, SwiftUI)                            │
│  - Device list, pairing wizard, settings                       │
│  - Photo browser window                                        │
│  - Trust prompts (ADB authorization)                           │
│  - XPC server: owns USB transports, ADB & MTP sessions         │
└─────────────────┬──────────────────────────────────────────────┘
                  │ XPC (Mach service)
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  FreeDroidFS.fskitmodule  (FSKit extension, sandboxed)         │
│  - Implements FSUnaryFileSystem / FSVolume                     │
│  - Translates Finder's POSIX-ish calls into transport ops      │
│  - Caches stat results, directory listings (TTL-based)         │
└────────────────────────────────────────────────────────────────┘

         ┌───── USB ─────┐
         │               │
    ┌────▼────┐    ┌─────▼─────┐
    │ adbd on │    │ MTP stack │
    │ device  │    │ on device │
    └─────────┘    └───────────┘
```

The FSKit extension is heavily sandboxed and cannot own USB devices or spawn processes; the main app owns the transports and the extension is a thin XPC proxy. This also lets the gallery, device list, and mounted volume share a single MTP/ADB session per device.

### 4.2 Clean Architecture + MVVM with feature-vertical slices

**Layer rule:** dependency arrows only point inward. Domain knows nothing about Data; Data knows nothing about Presentation.

```
┌──────────────────────────────────────────────────────────┐
│  Presentation  (Views + @Observable ViewModels)          │
│  Depends on: Domain only                                 │
└──────────────────────────────────────────────────────────┘
                          ▲
┌──────────────────────────────────────────────────────────┐
│  Domain  (Use Cases + Entities + Repository protocols)   │
│  Pure Swift, zero Foundation networking / SwiftUI        │
│  Depends on: nothing                                     │
└──────────────────────────────────────────────────────────┘
                          ▲
┌──────────────────────────────────────────────────────────┐
│  Data  (Repository implementations + Transport impls)    │
│  Depends on: Domain only                                 │
└──────────────────────────────────────────────────────────┘
```

Within these layers the code is organized as **feature-vertical Swift packages** so each feature can be opened in isolation.

### 4.3 Package layout

```
FreeDroid.xcworkspace
├── FreeDroid/                          App target
├── FreeDroidFS/                        FSKit extension target
└── Packages/
    ├── FreeDroidDomain/                Entities, UseCases, Repository protocols, Errors
    ├── FreeDroidData/                  Repository impls, ListingCache, ThumbnailCache, USB watcher
    ├── FreeDroidUI/                    Design system (Tokens, Surface, Controls, Feedback)
    ├── FreeDroidADB/                   adb binary wrapper, sync protocol
    ├── FreeDroidMTP/                   libmtp wrapper, USB session management
    ├── FreeDroidIPC/                   XPC contracts between app and FSKit extension
    └── Features/
        ├── DeviceManagement/           feature-specific UseCases + ViewModels + Views
        ├── FileBrowser/                feature-specific UseCases + ViewModels + Views
        ├── Gallery/                    feature-specific UseCases + ViewModels + Views
        └── Transfer/                   feature-specific UseCases + ViewModels + Views
```

**What goes where (resolves the layering question):**

- **`FreeDroidDomain`** owns shared entities, the universal protocols (`FileRepository`, `MediaRepository`, `TransferRepository`, `DeviceRepository`, `Transport`, `MountStrategy`), and cross-cutting UseCases.
- **`FreeDroidData`** owns shared infrastructure: USB watcher, repository implementations, caches, the composition glue that adapts transports to repositories. Features never re-implement these.
- **`Features/*`** are presentation-thick slices: feature-specific UseCases (e.g., `PairDeviceUseCase` for DeviceManagement), `@Observable` ViewModels, and SwiftUI Views. They consume the shared repositories from `FreeDroidData` via the protocols in `FreeDroidDomain` — they never create their own repository implementations.

**Dependency graph (strictly enforced):**

```
FreeDroid.app       → Features, UI, Data, IPC
FreeDroidFS         → Domain, IPC
Features/*          → Domain, UI                  (no direct dep on Data — wired by app)
Data                → Domain, ADB, MTP
ADB, MTP            → Domain
UI                  → (nothing — leaf)
Domain, IPC         → (nothing — leaves)
```

Features depend only on Domain protocols; the app target wires concrete Data implementations into Feature ViewModels at composition time. This keeps Features unit-testable without pulling Data into their build graph.

### 4.4 Mount strategy abstraction

A `MountStrategy` protocol in `FreeDroidDomain` allows swapping the mount implementation. v1.0 ships one impl; v1.x can add another for Mac App Store distribution without code churn.

```swift
public protocol MountStrategy: Sendable {
    var capabilities: MountCapabilities { get }
    func mount(_ device: Device, transport: any Transport) async throws -> MountedVolume
    func unmount(_ volume: MountedVolume) async throws
}
```

Implementations:
- **`FSKitMountStrategy`** (v1.0) — true POSIX mount, direct distribution
- **`FPXMountStrategy`** (v1.x, optional) — File Provider Extension, Mac App Store compatible
- **`MockMountStrategy`** — unit and snapshot tests

## 5. Domain Model

### 5.1 Core entities

```swift
public struct DeviceID: Hashable, Sendable { public let raw: String }
public struct RemotePath: Hashable, Sendable { public let raw: String }

public struct Device: Identifiable, Sendable {
    public let id: DeviceID
    public let displayName: String
    public let manufacturer: String
    public let model: String
    public let storageCapacityBytes: Int64?
    public let storageFreeBytes: Int64?
    public let transport: TransportKind
}

public enum TransportKind: Sendable { case adb, mtp, wifi }

public struct RemoteEntry: Sendable {
    public let path: RemotePath
    public let name: String
    public let kind: EntryKind
    public let sizeBytes: Int64?
    public let modifiedAt: Date?
    public let isHidden: Bool
}

public enum EntryKind: Sendable { case file, directory, symlink }

public struct MediaItem: Identifiable, Sendable {
    public let id: String
    public let path: RemotePath
    public let kind: MediaKind
    public let captureDate: Date?
    public let sizeBytes: Int64
}

public enum MediaKind: Sendable { case image, video }

public struct TransferJob: Identifiable, Sendable {
    public let id: UUID
    public let deviceID: DeviceID
    public let direction: Direction
    public let items: [RemotePath]
    public let destination: URL
}

public enum Direction: Sendable { case toMac, toDevice }
```

> `TransportKind` includes `.wifi` for forward compatibility only; v1.0 ships ADB + MTP. Adding `.wifi` later requires a new `Transport` implementation, not a domain change.

**Supporting types referenced in this spec** (all defined in `FreeDroidDomain`):

```swift
public struct DeviceInfo: Sendable {
    public let serial: String
    public let manufacturer: String
    public let model: String
    public let androidVersion: String?
    public let storageCapacityBytes: Int64?
    public let storageFreeBytes: Int64?
}

public struct MediaPage: Sendable {
    public let items: [MediaItem]
    public let hasMore: Bool
    public let nextPage: Int?
}

public enum ThumbnailSize: Sendable { case small, medium, large }

public struct TransferProgress: Sendable {
    public let jobID: UUID
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let currentItem: RemotePath?
    public let bytesPerSecond: Double
}

public enum TransferState: Sendable {
    case idle
    case running(TransferProgress)
    case paused(TransferProgress)
    case completed
    case failed(TransportError)
}

public struct MountCapabilities: Sendable {
    public let supportsTrueMount: Bool
    public let supportsWriteOps: Bool
    public let appearsInFinderSidebar: Bool
}

public struct MountedVolume: Sendable {
    public let deviceID: DeviceID
    public let mountURL: URL
    public let strategyKind: MountStrategyKind
}

public enum MountStrategyKind: Sendable { case fskit, fileProvider, mock }

public struct UserFacingError: Sendable {
    public let title: String
    public let message: String
    public let recoveryAction: RecoveryAction?
}

public enum RecoveryAction: Sendable {
    case retry
    case openSettings
    case authorizeOnDevice
    case contactSupport
}
```

### 5.2 Repository protocols (Domain layer)

```swift
public protocol DeviceRepository: Sendable {
    func observe() -> AsyncStream<[Device]>
    func device(_ id: DeviceID) async -> Device?
}

public protocol FileRepository: Sendable {
    func list(_ path: RemotePath) async throws -> [RemoteEntry]
    func stat(_ path: RemotePath) async throws -> RemoteEntry
    func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data
    func write(_ path: RemotePath, data: Data, offset: Int64) async throws
    func mkdir(_ path: RemotePath) async throws
    func remove(_ path: RemotePath) async throws
    func rename(_ from: RemotePath, to: RemotePath) async throws
}

public protocol MediaRepository: Sendable {
    func listMedia(in folder: RemotePath, page: Int) async throws -> MediaPage
    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> Data
}

public protocol TransferRepository: Sendable {
    func enqueue(_ job: TransferJob) async -> AsyncThrowingStream<TransferProgress, Error>
    func cancel(_ jobID: UUID) async
    func observe() -> AsyncStream<[TransferState]>
}
```

### 5.3 Transport protocol (Data layer contract)

```swift
public protocol Transport: AnyObject, Sendable {
    var deviceID: DeviceID { get }
    var capabilities: TransportCapabilities { get }
    var info: DeviceInfo { get async throws }
    func list(_ path: RemotePath) async throws -> [RemoteEntry]
    func stat(_ path: RemotePath) async throws -> RemoteEntry
    func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data
    func write(_ path: RemotePath, data: Data, offset: Int64) async throws
    func mkdir(_ path: RemotePath) async throws
    func remove(_ path: RemotePath) async throws
    func rename(_ from: RemotePath, to: RemotePath) async throws
    func close() async
}

public struct TransportCapabilities: Sendable {
    public let supportsRangeRead: Bool
    public let supportsRangeWrite: Bool
    public let supportsSymlinks: Bool
    public let recommendedChunkBytes: Int
}
```

### 5.4 Errors

```swift
public enum TransportError: Error, Sendable {
    case notConnected
    case unauthorized
    case timeout(Duration)
    case ioFailure(message: String)
    case notFound(RemotePath)
    case alreadyExists(RemotePath)
    case unsupported(reason: String)
    case cancelled
}
```

Each layer maps errors at its boundary: `TransportError` → POSIX `errno` at the FSKit boundary; `TransportError` → `UserFacingError` (title, message, action) at the UI boundary. Every user-facing error answers: what happened, what's recoverable, what action does the user have.

## 6. Transport Implementations

### 6.1 FreeDroidADB

- Bundles `adb` binary from Android Platform-Tools (Apache 2.0) in `FreeDroid.app/Contents/Resources/bin/adb`.
- Spawns a single long-lived `adb server` per app launch (port `5037`, configurable via `ANDROID_ADB_SERVER_PORT`).
- File operations use the `adb sync` protocol (push/pull) rather than `adb shell cat` for range I/O.
- Authorization flow surfaces a Trust prompt sheet in the UI when `adb` reports `unauthorized`, polling for state change.

### 6.2 FreeDroidMTP

- Wraps **libmtp** (LGPL 2.1) via a Swift C-interop layer with a Swift-typed surface.
- Built once into a SwiftPM `.xcframework` covering `arm64` (device) and `x86_64-simulator`.
- All calls are serialized through an `actor MTPSession` (libmtp is not thread-safe).
- Per-device quirk handling:
  - Samsung devices: chunk writes at 512MB to avoid connection resets
  - Pixel devices: send `LIBMTP_Dump_Device_Info` keepalive every 45s

### 6.3 Auto-selection

On device plug, the registry queries `adb devices`. If the device offers ADB and is authorized, ADB wins; otherwise MTP. Users can pin a preferred transport per device serial in settings.

## 7. FSKit Mount Strategy

### 7.1 Lifecycle

1. USB watcher (IOKit) emits a `deviceAttached` event.
2. `DeviceRegistry` opens the appropriate `Transport`.
3. App calls `FSFileSystemManager` API to register and mount a new volume named after the device.
4. macOS spins up the FSKit extension process, which connects to the app via XPC.
5. Finder operations route: Finder → FSKit callback → XPC → app → Transport.
6. On unplug or explicit eject, the extension drains pending ops and tears down the volume.

### 7.2 Implemented callbacks

| Callback | Maps to |
|---|---|
| `enumerateDirectory` | `adb sync ls` / `LIBMTP_Get_Files_And_Folders` |
| `lookupItem` | path → cached inode handle |
| `openItem` / `closeItem` | session-level handle |
| `readFile(offset:length:)` | `adb pull --partial` / MTP range read |
| `writeFile(offset:length:)` | `adb push --partial` / MTP chunked write |
| `createItem` / `removeItem` | mkdir / rm / touch |
| `renameItem` | atomic in-place rename |
| `attributes` | size, mtime, kind from listdir cache |

### 7.3 Safety & permissions

- Synthesized POSIX permissions: `0o755` for directories, `0o644` for files. Android exposes no meaningful permissions over ADB/MTP at this layer.
- Hidden files (`.foo`) marked Finder-hidden.
- Writes go to a `.partial` shadow path then atomic-rename at completion.
- Deletes move to `.FreeDroid/Trash/` on the device first (24h auto-purge), not immediate `rm`.
- All operations idempotent and resumable from last known offset across reconnects.

### 7.4 Caching

A three-layer cache lives in the app (the FSKit extension is stateless):

| Layer | Type | TTL / Cap | Notes |
|---|---|---|---|
| `ListingCache` | In-memory LRU | 60s TTL, 1000 entries | Invalidated on any write through us; persisted to disk on app quit |
| `ThumbnailCache` | Disk-LRU | 2GB cap | HEIC-encoded; keyed by `(deviceID, path, mtime, size)` |
| `ReadAheadBuffer` | Per-open-file ring | 1MB | Prefetches next 1MB on sequential reads |

All three implement a common `Cache` protocol with `get/put/invalidate/clear` so each is swappable and unit-testable in isolation.

## 8. UI Design System

### 8.1 Design language: "Glass over Grain"

- Base surfaces: `.regularMaterial` / `.ultraThinMaterial` (SwiftUI native vibrancy)
- Subtle film grain overlay for warmth (SVG noise, `mix-blend-mode: overlay` equivalent in Metal)
- One accent color: a deep electric green
- Typography: SF Pro for body, SF Pro Rounded for numerals
- Generous whitespace; quiet hierarchy

### 8.2 Theme system

Light and dark themes share **identical layout, motion, and components**; only color tokens differ. Defined in `FreeDroidUI/Tokens/Theme.swift` via `Color.adaptive(light:dark:)`. Accessed everywhere via `@Environment(\.theme)`. No hex literals outside the token file.

### 8.3 Signature interaction moments

| Moment | Implementation |
|---|---|
| **Living device ring** | `TimelineView` + `Canvas`; 3.2s breathe cycle when idle, fast spin during transfer. Color encodes transport (green=ADB, blue=MTP; purple reserved for Wi-Fi when added post-v1). |
| **Liquid transfer fill** | Metal shader filling the device card vertically from 0 to 100%, no modal dialog. |
| **Spatial photo grid** | Custom `MasonryLayout` implementing SwiftUI's `Layout` protocol; spring entry, hover parallax tilt, `matchedGeometryEffect` zoom on tap. |
| **Sidebar flow transitions** | Scale + opacity slide on view switches (no hard cuts). |
| **Floating command strip** | Bottom-pinned, appears only on selection. Hotkey chips fade in on `⌘` hold. |
| **Toast pearls** | Pill-shaped, stack with physics, drag-to-dismiss. |

### 8.4 Component library (`FreeDroidUI`)

```
FreeDroidUI/
├── Tokens/        Colors, Spacing, Radius, Motion (3 spring presets: crisp, smooth, lazy)
├── Surface/       MaterialPanel, GrainOverlay, Card, Sheet
├── Controls/      IconChip, Hotkey, CommandStrip, ToggleRow, PillTabs
├── Feedback/      FluidProgress, LivingRing, Toast, Spinner
├── Layout/        SidebarFlow, MasonryLayout, SectionHeader
└── Empty/         EmptyState
```

All motion goes through `Motion.swift` presets — no raw `.animation(.default)` calls. Every interaction must answer two of three: *delight, feedback, continuity*.

### 8.5 Code style

- **No inline comments.** Names and types carry meaning. SwiftLint rule flags `//` lines (excluding URLs, `MARK:` pragmas, and copyright headers).
- DocC `///` comments only on **public** API of packages meant for external consumption.

## 9. Concurrency & State

### 9.1 Actor topology

| Actor | Owns |
|---|---|
| `@MainActor` | All SwiftUI views and ViewModels |
| `DeviceRegistry` | Device list, attach/detach events |
| `ADBSession` (per device) | The `adb` process and sync channel |
| `MTPSession` (per device) | The libmtp device handle |
| `TransferQueue` (per device) | Active and pending transfer jobs |
| `ListingCache` (global) | Directory listing LRU |
| `ThumbnailCache` (global) | Disk-backed thumbnail cache |
| `XPCServer` (in app) | Hosts the Mach service; serves FSKit extension calls |
| `XPCClient` (in extension) | Calls into the app from the FSKit extension |

### 9.2 Reactive streams

`AsyncStream` and `AsyncChannel` (from `swift-async-algorithms`) replace Combine entirely. ViewModels expose `@Observable` properties; downstream views observe directly without `@Published`/`@StateObject` boilerplate.

### 9.3 Cancellation, retry, logging

- **Cancellation:** structured concurrency end-to-end. `Task.cancel()` propagates through `Transport` calls to interrupt underlying `adb` / MTP operations.
- **Retry:** transport-layer exponential backoff (3 attempts, 200ms / 800ms / 3.2s) for transient failures only. Permanent errors (auth, not-found) never retry.
- **Logging:** `os.Logger` with per-package subsystems. No `print`. Log levels mapped to user-facing diagnostic export.
- **Metrics:** a `MetricsSink` protocol with a no-op default. Future OSLog signposts or other sinks plug in without business-logic changes.

### 9.4 Multi-device handling

- One mounted volume per device (`/Volumes/Pixel 8 Pro`, `/Volumes/Galaxy S24`).
- Each device has its own `TransferQueue` so concurrent transfers across devices don't block each other.
- **Bus-aware scheduler:** transfers are queued per USB controller, not per device, to avoid oversubscribing a shared hub. v1 uses round-robin; the `BusScheduler` protocol allows swapping in QoS-aware scheduling later.

## 10. Dependency Injection

### 10.1 Hybrid strategy

- **Constructor injection** for the explicit dependency graph (repositories, use cases, ViewModels)
- **`swift-dependencies`** (Point-Free, Apache 2.0) for ambient concerns: clock, calendar, UUID, logger, file system, URLSession
- **`@Environment`** for SwiftUI view-scope concerns: theme, current device, command palette

### 10.2 Composition root

A single `AppContainer.swift` wires the explicit graph in roughly 80 readable lines. Process-local: the FSKit extension has its own `ExtensionContainer`.

### 10.3 Rationale

- Two processes → global containers are wrong. Explicit construction makes process boundaries obvious.
- OSS contributors read one file to understand the graph.
- No framework lock-in for the core graph.
- Strict concurrency-friendly: no global mutable state.
- `swift-dependencies` is reserved for stuff that genuinely *is* ambient, keeping `withDependencies { … }` hermetic test overrides usable everywhere.

## 11. Open-Source Plan

### 11.1 Licensing

| Component | License | Notes |
|---|---|---|
| App and most packages | **MIT** | Permissive, contributor-friendly |
| `FreeDroidMTP` package | **MPL 2.0** | File-level copyleft, compatible with libmtp's LGPL |
| Bundled `adb` (Google) | Apache 2.0 | NOTICE file preserved |
| Bundled `libmtp.dylib` | LGPL 2.1 | Dynamic-linked, source link in About |

A `THIRD_PARTY_NOTICES.md` is generated at build time and rendered in About → Acknowledgments.

### 11.2 Repository layout

```
FreeDroid/
├── README.md
├── LICENSE
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CHANGELOG.md
├── THIRD_PARTY_NOTICES.md
├── .github/
│   ├── workflows/ci.yml, release.yml, update-adb.yml
│   ├── ISSUE_TEMPLATE/
│   └── FUNDING.yml
├── docs/
│   ├── architecture.md
│   ├── design-system.md
│   ├── adb-protocol.md
│   └── mtp-quirks.md
├── FreeDroid.xcworkspace
├── FreeDroid/
├── FreeDroidFS/
├── Packages/
└── Resources/bin/adb
```

### 11.3 Distribution

| Channel | What | When |
|---|---|---|
| **GitHub Releases** | Signed, notarized `.dmg` (primary) | Every tagged release |
| **Homebrew Cask** | `brew install --cask freedroid` | Once stable; auto-PR'd by release workflow |
| **Sparkle 2 in-app updates** | EdDSA-signed appcast on GitHub Pages | From v0.2 |
| ~~Mac App Store~~ | Skipped for v1.0 | Revisit v1.x via `FPXMountStrategy` |

### 11.4 Signing & notarization

- Developer ID Application signing (existing $99/yr Apple Developer account).
- `com.apple.developer.fskit.fsmodule` entitlement, granted by Apple on request.
- Hardened runtime + `notarytool` step runs in GitHub Actions on tag push.
- Contributors without signing identity build unsigned dev builds locally with their personal team.

### 11.5 Versioning & cadence

- **SemVer**. Pre-1.0 minor bumps may break.
- **Conventional Commits** in PRs → auto-changelog via `git-cliff`.
- **release-please** bot opens a release PR when commits accumulate; merging triggers the release workflow.

### 11.6 Community

- **Discussions** for support, **Issues** for bugs only.
- Pinned **device compatibility tracker** issue with crowd-sourced markdown table.
- `good-first-issue` label seeded with UI polish, device quirks, localizations.
- **i18n** from v0.1 via `Localizable.xcstrings`; contributors PR translations directly.

## 12. Testing Strategy

### 12.1 Test pyramid

| Layer | Tool | Coverage |
|---|---|---|
| Unit (Domain) | Swift Testing | UseCases, entities, pure functions (~60%) |
| Unit (Presentation) | Swift Testing | ViewModel state transitions with stub repos (~20%) |
| Snapshot (UI) | `swift-snapshot-testing` | Every `FreeDroidUI` component, both themes (~10%) |
| Integration | Swift Testing + Android emulator | ADB push/pull, MTP roundtrip (~7%) |
| End-to-end (manual) | Real devices, checklist | FSKit mount, multi-device (~3%) |

### 12.2 Conventions

- **Swift Testing**, not XCTest. Parallel by default.
- Every Repository protocol has a `*RepositoryFake` in `FreeDroidDomain/Testing/`, shared across consumers' tests.
- Snapshot tests use a fixed reference simulator; record mode gated by env var to prevent accidental rebaselining.
- CI runs against Android emulator API 34 image via `setup-android-actions/setup-android`.
- **No mocking framework.** Protocol stubs and explicit test doubles only.

### 12.3 Performance budgets (enforced in CI signposted benchmarks)

| Operation | Budget |
|---|---|
| Cold mount + first directory shown | < 800ms |
| `listdir` 1000 files (cached) | < 50ms |
| `listdir` 1000 files (cold MTP) | < 4s |
| `listdir` 1000 files (cold ADB) | < 1s |
| Thumbnail generation per photo | < 100ms |
| Cmd+C / Cmd+V single 50MB file (ADB) | < 5s |
| UI frame time during transfer | 60fps (16.6ms budget) |

## 13. Risks & Open Questions

| Risk | Mitigation |
|---|---|
| Apple revokes FSKit entitlement | Add `FPXMountStrategy` ahead of time; ship both |
| libmtp build complexity on Apple Silicon | Use pre-built `.xcframework` checked into repo; CI rebuilds nightly |
| Per-device MTP quirks proliferate | Maintain `mtp-quirks.md` knowledge base; crowd-source via compatibility tracker |
| ADB binary updates from Google break sync protocol | Pin ADB version per release; weekly bot tests new versions |
| FSKit + XPC latency hurts directory listings | Three-layer cache + readahead buffer (Section 7.4) |
| OSS contributors blocked by signing identity | Document unsigned dev-build path in CONTRIBUTING.md |

## 14. Glossary

- **ADB** — Android Debug Bridge. Requires USB debugging on device; fastest transport.
- **MTP** — Media Transfer Protocol. Works on any Android with no setup; slower.
- **FSKit** — Apple's in-process filesystem extension API (macOS 15.4+).
- **FPX** — File Provider Extension. Cloud-storage-style filesystem extension; MAS-compatible.
- **XPC** — Cross-Process Communication. macOS IPC mechanism used between the app and the FSKit extension.
- **libmtp** — Open-source MTP client library, LGPL 2.1.
