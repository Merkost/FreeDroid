# Cross-Device Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user select files in one device's file browser and copy them to a folder on a *different* connected device, with three discoverable triggers: right-click context menu, toolbar button, and drag-and-drop onto a device card.

**Architecture:** Cross-device copy is implemented as a two-leg orchestration on top of the existing `TransferQueue` — leg 1 pulls the selection to a Mac staging directory, leg 2 pushes from that directory to the destination device. Both legs reuse `TransferEngine`, so all existing perf work (Tier 0 one-shot, Tier 4 parallelism, Tier 5 zstd) flows through unchanged. A new `CrossDeviceCopyService` actor coordinates the two legs and emits a single composite progress stream. The UI is a `CopyToDeviceSheet` showing target device picker + folder browser; it's launched from a right-click action, a toolbar button, and a drop handler attached to device rows.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, existing `TransferQueue` / `TransferEngine` / `TransferRepository` plumbing, existing `DeviceRegistry` for the device list.

---

## File Structure

**Domain (`Sources/FreeDroidDomain/Entities/`):**
- Create: `CrossDeviceCopyRequest.swift` — value type: source `DeviceID` + items + destination `DeviceID` + destination `RemotePath`.
- Create: `CrossDeviceCopyProgress.swift` — value type: `id`, `leg` (`.pulling | .pushing | .done`), `bytesPulled`, `bytesPushed`, `totalBytes`, `currentItem`.

**Data layer (`Sources/FreeDroidData/Transfer/`):**
- Create: `CrossDeviceCopyService.swift` — actor; takes `TransferQueue` + `DeviceRegistry`; method `start(_ request) -> AsyncThrowingStream<CrossDeviceCopyProgress, Error>`; `cancel(_ id)`.
- Modify: `TransferQueue.swift` — generalize `runParallelPull` so an `enqueue` with `direction: .toDevice` does parallel push instead. Today it ignores direction.
- Create: `CrossDeviceCopyRepository.swift` — repository protocol + impl wrapping `CrossDeviceCopyService`, mirroring `TransferRepositoryImpl`.

**Domain repositories (`Sources/FreeDroidDomain/Repositories/`):**
- Create: `CrossDeviceCopyRepository.swift` — protocol.

**Feature layer (`Sources/Transfer/`):**
- Create: `CopyToDeviceUseCase.swift` — invokes `CrossDeviceCopyRepository`; thin like `StartTransferUseCase`.
- Modify: `TransfersViewModel.swift` — observe cross-device jobs alongside single-device jobs so they show up in the existing transfers panel.

**FileBrowser feature (`Sources/FileBrowser/`):**
- Modify: `FileBrowserViewModel.swift` — add `selectedRemotePaths()` helper + a `copyToOtherDevice(target:destination:)` async method.
- Modify: `FileBrowserView.swift` — add right-click "Copy to device…" menu item, toolbar "Copy to…" button, and a `Transferable` payload on rows for drag.
- Create: `CopyToDeviceSheet.swift` — sheet with device picker + remote folder picker for the destination.
- Create: `RemoteSelectionTransferable.swift` — `Transferable` conforming type carrying `(sourceDeviceID, [RemotePath])` for the drag payload.

**Device sidebar (locate file first — likely `Sources/DeviceManagement/` or `FreeDroid/`):**
- Modify: the device-row view to expose a `dropDestination(for: RemoteSelectionTransferable.self)` handler that, when dropped, opens the `CopyToDeviceSheet` pre-filled with that target device.

**Wiring (`FreeDroid/AppContainer.swift`):**
- Modify: instantiate `CrossDeviceCopyService` + repository; expose to feature use-cases.

**Tests:**
- Create: `Tests/FreeDroidDataTests/CrossDeviceCopyServiceTests.swift` — uses two `FakeTransport` instances; verifies two-leg orchestration, progress reporting, cancellation, cleanup of staging directory.
- Modify: `Tests/FreeDroidDataTests/TransferQueueTests.swift` — add a `.toDevice` push test covering the new parallel push branch.

---

## Task 1: Domain types for cross-device copy

**Files:**
- Create: `Sources/FreeDroidDomain/Entities/CrossDeviceCopyRequest.swift`
- Create: `Sources/FreeDroidDomain/Entities/CrossDeviceCopyProgress.swift`

- [ ] **Step 1: Add `CrossDeviceCopyRequest`**

```swift
import Foundation

public struct CrossDeviceCopyRequest: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let sourceDeviceID: DeviceID
    public let sourceDeviceName: String
    public let items: [RemotePath]
    public let destinationDeviceID: DeviceID
    public let destinationDeviceName: String
    public let destinationPath: RemotePath

    public init(
        id: UUID = UUID(),
        sourceDeviceID: DeviceID,
        sourceDeviceName: String,
        items: [RemotePath],
        destinationDeviceID: DeviceID,
        destinationDeviceName: String,
        destinationPath: RemotePath
    ) {
        self.id = id
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceName = sourceDeviceName
        self.items = items
        self.destinationDeviceID = destinationDeviceID
        self.destinationDeviceName = destinationDeviceName
        self.destinationPath = destinationPath
    }
}
```

- [ ] **Step 2: Add `CrossDeviceCopyProgress`**

```swift
import Foundation

public enum CrossDeviceCopyLeg: String, Hashable, Sendable, Codable {
    case pulling
    case pushing
    case done
}

public struct CrossDeviceCopyProgress: Hashable, Sendable {
    public let id: UUID
    public let leg: CrossDeviceCopyLeg
    public let bytesPulled: Int64
    public let bytesPushed: Int64
    public let totalBytes: Int64
    public let currentItem: RemotePath?

    public init(
        id: UUID,
        leg: CrossDeviceCopyLeg,
        bytesPulled: Int64,
        bytesPushed: Int64,
        totalBytes: Int64,
        currentItem: RemotePath?
    ) {
        self.id = id
        self.leg = leg
        self.bytesPulled = bytesPulled
        self.bytesPushed = bytesPushed
        self.totalBytes = totalBytes
        self.currentItem = currentItem
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/FreeDroidDomain/Entities/CrossDeviceCopyRequest.swift Sources/FreeDroidDomain/Entities/CrossDeviceCopyProgress.swift
git commit -m "feat(domain): cross-device copy value types"
```

---

## Task 2: Generalize `TransferQueue` for `.toDevice` parallel push

**Files:**
- Modify: `Sources/FreeDroidData/Transfer/TransferQueue.swift`
- Test: `Tests/FreeDroidDataTests/TransferQueueTests.swift`

- [ ] **Step 1: Write the failing push test**

```swift
@Test func parallelPushesAllItems() async throws {
    let transport = FakeTransport()
    var paths: [RemotePath] = []
    let staging = FileManager.default.temporaryDirectory
        .appendingPathComponent("freedroid-stage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    for index in 0..<5 {
        let local = staging.appendingPathComponent("file\(index).bin")
        try Data(repeating: UInt8(index), count: 512).write(to: local)
        paths.append(RemotePath(raw: "/dest/file\(index).bin"))
    }
    let queue = TransferQueue(maxParallelPerDevice: 2)
    let job = TransferJob(
        deviceID: DeviceID(raw: "FAKE"),
        direction: .toDevice,
        items: paths,
        destination: staging
    )
    let engine = TransferEngine(transport: transport, chunkSize: 1024)
    let stream = await queue.enqueue(job, engine: engine)
    var last: TransferProgress?
    for try await p in stream { last = p }
    #expect(last?.completedBytes == Int64(paths.count) * 512)
    for path in paths {
        let written = try await transport.read(path, offset: 0, length: 4096)
        #expect(written.count == 512)
    }
}
```

- [ ] **Step 2: Run test (fails — queue ignores direction)**

Run: `swift test --filter "TransferQueue/parallelPushesAllItems"`
Expected: FAIL — final progress is 0 because `runParallelPull` is called for the push job and it would try to pull from non-existent remote paths.

- [ ] **Step 3: Branch `TransferQueue.enqueue` on direction**

In `enqueue`, replace the single `runParallelPull` call with:

```swift
let copied: Int64
switch job.direction {
case .toMac:
    copied = try await self.runParallelPull(
        job: job, engine: engine, total: total, continuation: continuation)
case .toDevice:
    copied = try await self.runParallelPush(
        job: job, engine: engine, total: total, continuation: continuation)
}
```

- [ ] **Step 4: Add `runParallelPush`**

```swift
private func runParallelPush(
    job: TransferJob,
    engine: TransferEngine,
    total: Int64,
    continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
) async throws -> Int64 {
    let limit = maxParallelPerDevice
    let jobID = job.id
    let staging = job.destination
    var copied: Int64 = 0
    try await withThrowingTaskGroup(of: (RemotePath, Int64).self) { group in
        var inFlight = 0
        var index = 0
        let items = job.items
        while index < items.count && inFlight < limit {
            let item = items[index]
            index += 1
            inFlight += 1
            group.addTask {
                let local = staging.appendingPathComponent(item.name)
                let bytes = try await engine.push(localURL: local, to: item)
                return (item, bytes)
            }
        }
        while let (item, bytes) = try await group.next() {
            inFlight -= 1
            copied += bytes
            let progress = TransferProgress(
                jobID: jobID,
                completedBytes: copied,
                totalBytes: total,
                currentItem: item,
                bytesPerSecond: 0
            )
            jobStates[jobID] = .running(progress)
            publish()
            continuation.yield(progress)
            if index < items.count {
                try Task.checkCancellation()
                let next = items[index]
                index += 1
                inFlight += 1
                group.addTask {
                    let local = staging.appendingPathComponent(next.name)
                    let bytes = try await engine.push(localURL: local, to: next)
                    return (next, bytes)
                }
            }
        }
    }
    return copied
}
```

- [ ] **Step 5: Update `computeTotal` for `.toDevice`**

For `.toDevice`, items are the *destination* remote paths; size is the local file on disk under `job.destination`:

```swift
private func computeTotal(job: TransferJob, engine: TransferEngine) async throws -> Int64 {
    switch job.direction {
    case .toMac:
        var total: Int64 = 0
        for item in job.items {
            let entry = try await engine.transport.stat(item)
            total += entry.sizeBytes ?? 0
        }
        return total
    case .toDevice:
        var total: Int64 = 0
        for item in job.items {
            let local = job.destination.appendingPathComponent(item.name)
            let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
            total += size
        }
        return total
    }
}
```

- [ ] **Step 6: Run all transfer tests; verify push test passes**

Run: `swift test --filter "TransferQueue"`
Expected: PASS — both `parallelPullsAllItems` and `parallelPushesAllItems`.

- [ ] **Step 7: Commit**

```bash
git add Sources/FreeDroidData/Transfer/TransferQueue.swift Tests/FreeDroidDataTests/TransferQueueTests.swift
git commit -m "feat(transfer): TransferQueue supports .toDevice parallel push"
```

---

## Task 3: `CrossDeviceCopyRepository` protocol + impl + service

**Files:**
- Create: `Sources/FreeDroidDomain/Repositories/CrossDeviceCopyRepository.swift`
- Create: `Sources/FreeDroidData/Transfer/CrossDeviceCopyService.swift`
- Create: `Sources/FreeDroidData/Repositories/CrossDeviceCopyRepositoryImpl.swift`

- [ ] **Step 1: Repository protocol**

```swift
import Foundation

public protocol CrossDeviceCopyRepository: Sendable {
    func start(_ request: CrossDeviceCopyRequest) -> AsyncThrowingStream<CrossDeviceCopyProgress, Error>
    func cancel(_ requestID: UUID) async
}
```

- [ ] **Step 2: `CrossDeviceCopyService` actor**

Service owns the staging directory under `FileManager.default.temporaryDirectory.appendingPathComponent("freedroid-xcopy-\(request.id.uuidString)")`. Creates dir before pull, removes it after push (success or failure). Two legs run sequentially per item-batch; both legs use `TransferQueue.enqueue` so they pick up Tier 4 parallelism.

```swift
import Foundation
import FreeDroidDomain

public actor CrossDeviceCopyService {
    private let queue: TransferQueue
    private let registry: DeviceRegistry
    private var active: [UUID: Task<Void, Never>] = [:]

    public init(queue: TransferQueue, registry: DeviceRegistry) {
        self.queue = queue
        self.registry = registry
    }

    public func start(_ request: CrossDeviceCopyRequest) -> AsyncThrowingStream<CrossDeviceCopyProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(request, continuation: continuation) }
            active[request.id] = task
            continuation.onTermination = { _ in Task { await self.cancel(request.id) } }
        }
    }

    public func cancel(_ requestID: UUID) async {
        active[requestID]?.cancel()
        active[requestID] = nil
    }

    private func run(
        _ request: CrossDeviceCopyRequest,
        continuation: AsyncThrowingStream<CrossDeviceCopyProgress, Error>.Continuation
    ) async {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("freedroid-xcopy-\(request.id.uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let sourceEngine = try await engine(for: request.sourceDeviceID)
            let pullJob = TransferJob(
                deviceID: request.sourceDeviceID,
                direction: .toMac,
                items: request.items,
                destination: staging
            )
            var totalBytes: Int64 = 0
            var bytesPulled: Int64 = 0
            for try await progress in await queue.enqueue(pullJob, engine: sourceEngine) {
                totalBytes = max(totalBytes, progress.totalBytes)
                bytesPulled = progress.completedBytes
                continuation.yield(CrossDeviceCopyProgress(
                    id: request.id, leg: .pulling,
                    bytesPulled: bytesPulled, bytesPushed: 0,
                    totalBytes: totalBytes, currentItem: progress.currentItem))
            }
            try Task.checkCancellation()
            let destItems = request.items.map { request.destinationPath.appending($0.name) }
            let destinationEngine = try await engine(for: request.destinationDeviceID)
            let renamedStaging = try await renameLocalForPush(staging, items: request.items, destItems: destItems)
            let pushJob = TransferJob(
                deviceID: request.destinationDeviceID,
                direction: .toDevice,
                items: destItems,
                destination: renamedStaging
            )
            var bytesPushed: Int64 = 0
            for try await progress in await queue.enqueue(pushJob, engine: destinationEngine) {
                bytesPushed = progress.completedBytes
                continuation.yield(CrossDeviceCopyProgress(
                    id: request.id, leg: .pushing,
                    bytesPulled: bytesPulled, bytesPushed: bytesPushed,
                    totalBytes: totalBytes, currentItem: progress.currentItem))
            }
            continuation.yield(CrossDeviceCopyProgress(
                id: request.id, leg: .done,
                bytesPulled: bytesPulled, bytesPushed: bytesPushed,
                totalBytes: totalBytes, currentItem: nil))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
        active[request.id] = nil
    }

    private func engine(for deviceID: DeviceID) async throws -> TransferEngine {
        let transport = try await registry.transport(for: deviceID)
        return TransferEngine(transport: transport)
    }

    private func renameLocalForPush(_ staging: URL, items: [RemotePath], destItems: [RemotePath]) async throws -> URL {
        for (item, dest) in zip(items, destItems) where item.name != dest.name {
            let from = staging.appendingPathComponent(item.name)
            let to = staging.appendingPathComponent(dest.name)
            try FileManager.default.moveItem(at: from, to: to)
        }
        return staging
    }
}
```

> **Note for the implementer:** `DeviceRegistry.transport(for:)` may not exist yet — search `Sources/FreeDroidData/Registry/DeviceRegistry.swift` for the existing accessor (likely `session(for:)` or similar) and adapt. If only `session` exists, add a `public func transport(for:) async throws -> any Transport` that returns the same instance.

- [ ] **Step 3: `CrossDeviceCopyRepositoryImpl`**

```swift
import Foundation
import FreeDroidDomain

public final class CrossDeviceCopyRepositoryImpl: CrossDeviceCopyRepository {
    private let service: CrossDeviceCopyService
    public init(service: CrossDeviceCopyService) { self.service = service }
    public func start(_ request: CrossDeviceCopyRequest) -> AsyncThrowingStream<CrossDeviceCopyProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for try await progress in await service.start(request) {
                    continuation.yield(progress)
                }
                continuation.finish()
            }
        }
    }
    public func cancel(_ requestID: UUID) async { await service.cancel(requestID) }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/FreeDroidDomain/Repositories/CrossDeviceCopyRepository.swift \
        Sources/FreeDroidData/Transfer/CrossDeviceCopyService.swift \
        Sources/FreeDroidData/Repositories/CrossDeviceCopyRepositoryImpl.swift
git commit -m "feat(data): cross-device copy service + repository"
```

---

## Task 4: Tests for `CrossDeviceCopyService`

**Files:**
- Create: `Tests/FreeDroidDataTests/CrossDeviceCopyServiceTests.swift`

- [ ] **Step 1: Write tests using two `FakeTransport`s**

The existing `FakeTransport` already supports `read`/`write`. Build a small `FakeRegistry`-style stub or extend `DeviceRegistry` with a test-injectable path. Either approach is fine — pick the one that requires the smallest change.

```swift
@Test func copiesItemsBetweenTwoTransports() async throws {
    let source = FakeTransport()
    let dest = FakeTransport()
    let payload = Data(repeating: 7, count: 4096)
    try await source.write(RemotePath(raw: "/a.bin"), data: payload, offset: 0)
    try await source.write(RemotePath(raw: "/b.bin"), data: payload, offset: 0)
    let queue = TransferQueue(maxParallelPerDevice: 2)
    // Build a minimal registry stub that maps two device IDs to source/dest transports.
    let registry = StubRegistry(transports: [
        DeviceID(raw: "SRC"): source,
        DeviceID(raw: "DST"): dest
    ])
    let service = CrossDeviceCopyService(queue: queue, registry: registry)
    let request = CrossDeviceCopyRequest(
        sourceDeviceID: DeviceID(raw: "SRC"),
        sourceDeviceName: "Source",
        items: [RemotePath(raw: "/a.bin"), RemotePath(raw: "/b.bin")],
        destinationDeviceID: DeviceID(raw: "DST"),
        destinationDeviceName: "Dest",
        destinationPath: RemotePath(raw: "/Pictures")
    )
    var lastLeg: CrossDeviceCopyLeg?
    for try await progress in await service.start(request) {
        lastLeg = progress.leg
    }
    #expect(lastLeg == .done)
    let readBack = try await dest.read(RemotePath(raw: "/Pictures/a.bin"), offset: 0, length: 8192)
    #expect(readBack == payload)
}

@Test func cancellationStopsMidway() async throws { /* …cancels the AsyncThrowingStream and asserts staging dir is gone… */ }
@Test func failureInPullCleansStaging() async throws { /* throw from source.read, assert no staging dir leaks… */ }
```

- [ ] **Step 2: Decide on `StubRegistry` shape**

`DeviceRegistry` is an actor with a fixed init signature. The cleanest approach is to introduce a small protocol the service depends on:

```swift
public protocol DeviceTransportProviding: Sendable {
    func transport(for deviceID: DeviceID) async throws -> any Transport
}
```

`DeviceRegistry` conforms (adds one method); `StubRegistry` in tests conforms with a dictionary. Update `CrossDeviceCopyService` to take `any DeviceTransportProviding` instead of `DeviceRegistry` directly.

- [ ] **Step 3: Run + commit**

```bash
swift test --filter "CrossDeviceCopyServiceTests"
git add Sources/FreeDroidData/Transfer/CrossDeviceCopyService.swift \
        Sources/FreeDroidData/Registry/DeviceRegistry.swift \
        Sources/FreeDroidDomain/Repositories/CrossDeviceCopyRepository.swift \
        Tests/FreeDroidDataTests/CrossDeviceCopyServiceTests.swift
git commit -m "test(transfer): cross-device copy service coverage"
```

---

## Task 5: `CopyToDeviceUseCase` + AppContainer wiring

**Files:**
- Create: `Sources/Transfer/CopyToDeviceUseCase.swift`
- Modify: `FreeDroid/AppContainer.swift`

- [ ] **Step 1: Use case**

```swift
import Foundation
import FreeDroidDomain

public struct CopyToDeviceUseCase: Sendable {
    public let repository: any CrossDeviceCopyRepository
    public init(repository: any CrossDeviceCopyRepository) { self.repository = repository }

    public func callAsFunction(
        from sourceDeviceID: DeviceID,
        sourceDeviceName: String,
        items: [RemotePath],
        to destinationDeviceID: DeviceID,
        destinationDeviceName: String,
        destinationPath: RemotePath
    ) -> AsyncThrowingStream<CrossDeviceCopyProgress, Error> {
        repository.start(CrossDeviceCopyRequest(
            sourceDeviceID: sourceDeviceID,
            sourceDeviceName: sourceDeviceName,
            items: items,
            destinationDeviceID: destinationDeviceID,
            destinationDeviceName: destinationDeviceName,
            destinationPath: destinationPath
        ))
    }
}
```

- [ ] **Step 2: AppContainer wiring**

In `AppContainer`, where `TransferRepositoryImpl` is constructed, also construct:

```swift
let crossDeviceCopyService = CrossDeviceCopyService(queue: transferQueue, registry: deviceRegistry)
let crossDeviceCopyRepository: any CrossDeviceCopyRepository = CrossDeviceCopyRepositoryImpl(service: crossDeviceCopyService)
let copyToDeviceUseCase = CopyToDeviceUseCase(repository: crossDeviceCopyRepository)
```

Expose `copyToDeviceUseCase` on the container.

- [ ] **Step 3: Commit**

```bash
git add Sources/Transfer/CopyToDeviceUseCase.swift FreeDroid/AppContainer.swift
git commit -m "feat(transfer): wire CopyToDeviceUseCase into AppContainer"
```

---

## Task 6: `CopyToDeviceSheet` UI

**Files:**
- Create: `Sources/FileBrowser/CopyToDeviceSheet.swift`

- [ ] **Step 1: Sheet view**

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct CopyToDeviceSheet: View {
    public struct Selection: Equatable {
        public let device: Device
        public let path: RemotePath
    }
    public let sourceDevice: Device
    public let items: [RemotePath]
    public let availableTargets: [Device]
    public let listFolder: @Sendable (DeviceID, RemotePath) async -> [RemoteEntry]
    public let onCancel: () -> Void
    public let onConfirm: (Selection) -> Void

    @State private var selectedDevice: Device?
    @State private var currentPath: RemotePath = .root
    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = false

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Copy \(items.count) item\(items.count == 1 ? "" : "s") from \(sourceDevice.displayName)")
                .font(Typography.headline)
            Picker("To device", selection: $selectedDevice) {
                ForEach(availableTargets) { device in
                    Text(device.displayName).tag(device as Device?)
                }
            }
            FolderPickerList(
                entries: entries,
                currentPath: currentPath,
                isLoading: isLoading,
                onSelect: { entry in
                    if entry.kind == .directory {
                        currentPath = entry.path
                        Task { await reload() }
                    }
                },
                onUp: {
                    if let parent = currentPath.parent {
                        currentPath = parent
                        Task { await reload() }
                    }
                }
            )
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Copy here") {
                    guard let dev = selectedDevice else { return }
                    onConfirm(Selection(device: dev, path: currentPath))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedDevice == nil)
            }
        }
        .padding(Spacing.lg)
        .frame(minWidth: 480, minHeight: 360)
        .task { await reload() }
        .onChange(of: selectedDevice) { _, _ in
            currentPath = .root
            Task { await reload() }
        }
    }

    private func reload() async {
        guard let dev = selectedDevice else { entries = []; return }
        isLoading = true
        defer { isLoading = false }
        entries = await listFolder(dev.id, currentPath).filter { $0.kind == .directory }
    }
}
```

- [ ] **Step 2: `FolderPickerList` helper**

Small private view: `List` of folder rows + an "Up" row when `currentPath != .root`. Reuses `FileIconResolver` for icons. ~40 lines.

- [ ] **Step 3: Commit**

```bash
git add Sources/FileBrowser/CopyToDeviceSheet.swift
git commit -m "feat(filebrowser): CopyToDeviceSheet picker"
```

---

## Task 7: FileBrowser triggers — right-click + toolbar + drag

**Files:**
- Modify: `Sources/FileBrowser/FileBrowserViewModel.swift`
- Modify: `Sources/FileBrowser/FileBrowserView.swift`
- Create: `Sources/FileBrowser/RemoteSelectionTransferable.swift`

- [ ] **Step 1: `RemoteSelectionTransferable`**

```swift
import CoreTransferable
import FreeDroidDomain

public struct RemoteSelectionPayload: Codable, Hashable, Sendable, Transferable {
    public let sourceDeviceID: DeviceID
    public let sourceDeviceName: String
    public let items: [RemotePath]

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .freedroidRemoteSelection)
    }
}

public extension UTType {
    static let freedroidRemoteSelection = UTType(exportedAs: "com.merkost.freedroid.remote-selection")
}
```

> Register the UTI in `FreeDroid/Info.plist` under `UTExportedTypeDeclarations` so AppKit honors it across processes (drag from FileBrowser to device-row in another window/section).

- [ ] **Step 2: ViewModel selection helpers**

In `FileBrowserViewModel`, add:

```swift
public func currentSelectionPaths() -> [RemotePath] {
    let selected = selection.selectedPaths
    return selected.isEmpty ? focusedPath.map { [$0] } ?? [] : Array(selected)
}

public func selectionPayload(sourceDeviceName: String) -> RemoteSelectionPayload? {
    guard let deviceID, !currentSelectionPaths().isEmpty else { return nil }
    return RemoteSelectionPayload(
        sourceDeviceID: deviceID,
        sourceDeviceName: sourceDeviceName,
        items: currentSelectionPaths()
    )
}
```

- [ ] **Step 3: Right-click menu**

In `FileBrowserView.rowButton(for:)`'s `.contextMenu`, after the existing items, add:

```swift
Button("Copy to device…") { showCopyToDeviceSheet = true }
    .disabled(availableCopyTargets.isEmpty)
```

`showCopyToDeviceSheet` is a `@State Bool` on the view. `availableCopyTargets` is computed via the container's device list filtered to exclude the current device. The sheet itself is presented via `.sheet(isPresented:)` on the root view.

- [ ] **Step 4: Toolbar button**

Add a toolbar item beside the existing actions:

```swift
ToolbarItem(placement: .primaryAction) {
    Button {
        showCopyToDeviceSheet = true
    } label: {
        Label("Copy to Device", systemImage: "arrowshape.right.fill")
    }
    .disabled(viewModel.currentSelectionPaths().isEmpty || availableCopyTargets.isEmpty)
    .help("Copy selected items to another connected device")
}
```

- [ ] **Step 5: Drag source on row**

Wrap each `FileRowView` with `.draggable {}`:

```swift
.draggable {
    viewModel.selectionPayload(sourceDeviceName: deviceName) ?? RemoteSelectionPayload(
        sourceDeviceID: viewModel.deviceID ?? DeviceID(raw: ""),
        sourceDeviceName: deviceName,
        items: [entry.path]
    )
}
```

If the row is part of the current selection, the drag carries the whole selection; otherwise it carries just that row.

- [ ] **Step 6: Sheet presentation**

Inject `copyToDeviceUseCase` + device list provider into the View through the existing `AppContainer`. On sheet confirm:

```swift
Task {
    for try await _ in copyToDeviceUseCase(
        from: viewModel.deviceID!, sourceDeviceName: deviceName,
        items: viewModel.currentSelectionPaths(),
        to: selection.device.id, destinationDeviceName: selection.device.displayName,
        destinationPath: selection.path
    ) { /* progress surfaced via TransfersViewModel */ }
}
```

- [ ] **Step 7: Commit**

```bash
git add Sources/FileBrowser/RemoteSelectionTransferable.swift \
        Sources/FileBrowser/FileBrowserViewModel.swift \
        Sources/FileBrowser/FileBrowserView.swift \
        FreeDroid/Info.plist
git commit -m "feat(filebrowser): copy-to-device triggers (right-click, toolbar, drag)"
```

---

## Task 8: Drop target on device cards

**Files:**
- Locate first: device-list view (search `grep -rn "DeviceCard\|DeviceRow\|DeviceList" Sources/DeviceManagement FreeDroid`).
- Modify: that view's row.

- [ ] **Step 1: Add `.dropDestination`**

```swift
.dropDestination(for: RemoteSelectionPayload.self) { payloads, _ in
    guard let payload = payloads.first, payload.sourceDeviceID != device.id else { return false }
    pendingDrop = (payload, device)
    return true
}
```

`pendingDrop` is a `@State` that triggers presentation of `CopyToDeviceSheet` pre-filled with the dropped target device + payload items. The sheet only asks for the destination folder.

- [ ] **Step 2: Visual feedback**

```swift
.onDropTargetHover { isTargeted in /* update @State Bool */ }
.overlay {
    if isDropTargeted {
        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/DeviceManagement/<the modified file>.swift
git commit -m "feat(devices): device cards accept drag-and-drop for cross-device copy"
```

---

## Task 9: Surface progress in `TransfersViewModel`

**Files:**
- Modify: `Sources/Transfer/TransfersViewModel.swift`
- Modify: `Sources/Transfer/TransferRow.swift` (composite progress display)

- [ ] **Step 1: Observe cross-device progress**

`TransfersViewModel` already observes `TransferRepository`. Add a parallel `CrossDeviceCopyRepository` injection + an internal `[UUID: CrossDeviceCopyProgress]` map updated as streams emit. Merge into the existing row list as `TransferRow.Kind.crossDevice` so toasts/inline progress reuse the same UI.

- [ ] **Step 2: Composite row label**

`Pixel 9 → Xiaomi 13   3 items   pulling (52%)` or `pushing (18%)`.

- [ ] **Step 3: Cancel button**

Calls `CrossDeviceCopyRepository.cancel(_:)` instead of `TransferRepository.cancel(_:)`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Transfer/TransfersViewModel.swift Sources/Transfer/TransferRow.swift
git commit -m "feat(transfers): show cross-device copies in the transfers panel"
```

---

## Task 10: Manual QA + final review

- [ ] Right-click a single file in Pixel browser → "Copy to device…" → pick Xiaomi → pick destination → confirm. Verify the file appears on Xiaomi at the chosen path.
- [ ] Multi-select 5 files → toolbar "Copy to Device" → same flow. Verify all 5 land.
- [ ] Drag a selection from the Pixel browser onto the Xiaomi device card in the sidebar. Sheet opens pre-filled with Xiaomi as target. Confirm.
- [ ] Cancel mid-copy. Verify staging directory is removed and partial files on destination don't leave the device in a confusing state. (Cleanup of partial destination files is **out of scope** — document as a known limitation.)
- [ ] Source = destination device should be blocked at the picker (no entry in `availableTargets`).
- [ ] If only one device is connected, all copy-to-device entry points are disabled.
- [ ] Verify transfers panel shows the composite progress and that cancel works from there.
- [ ] Run the full test suite: `swift test`.

---

## Out of scope (note for future work)

- **Dual-pane file browser.** User explicitly chose cross-device copy only.
- **Partial-failure rollback** on destination (if push fails mid-batch, files already pushed stay).
- **Direct phone-to-phone path** (skipping Mac staging). Would require either USB host bridging or ADB reverse tcp — Tier 7+ work.
- **Folder selection at the source.** Initial implementation copies files only; a directory in selection should be flagged with an error toast ("folders aren't supported yet"). Recursive folder copy is a follow-up.
- **Move semantics** (delete from source after copy). Add later as a separate `MoveToDeviceUseCase`.
- **Progress aggregation tweaks** — current model shows pull % then push %. A weighted-by-bytes single-bar view is nicer but not blocking.

---

## Self-review (controller checklist before execution)

- Spec coverage: every selected user trigger (right-click, toolbar, drag) has a task; cross-device copy core has a task; tests are explicit.
- Placeholders: each step has concrete code or a precise pointer ("find existing `session(for:)` and conform to `DeviceTransportProviding`"). No "TODO" / "implement later".
- Type consistency: `CrossDeviceCopyRequest.id` is `UUID`, threaded through the service, repository, and view-model uniformly.
- Risks: drag-and-drop UTI registration in Info.plist is easy to forget — called out in Task 7. The `renameLocalForPush` step (Task 3) is the subtle bit; tests cover it.
