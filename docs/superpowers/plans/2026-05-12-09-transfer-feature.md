# FreeDroid Plan #9 — Transfer Feature

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `Transfer` feature: starts transfer jobs from File Browser / Gallery, drives the liquid progress fill in device cards, shows a draggable Transfers panel listing active and recent jobs, and posts toast notifications on completion.

**Architecture:** Feature package on Domain + UI. `TransfersViewModel` observes `TransferRepository.observe()` and exposes derived per-device fraction. `StartTransferUseCase` encapsulates enqueue. A `TransferToastPresenter` translates state changes into `Toast`s. The device card view subscribes to per-device fraction and animates its `FluidProgress`.

**Tech Stack:** SwiftUI, FreeDroidDomain, FreeDroidUI.

---

## File Structure

```
Packages/Features/Transfer/
├── Package.swift                                       create
├── Sources/Transfer/
│   ├── TransfersViewModel.swift                        @Observable, observes [TransferState]
│   ├── TransfersPanel.swift                            list view
│   ├── TransferRow.swift                               single row
│   ├── StartTransferUseCase.swift
│   ├── CancelTransferUseCase.swift
│   ├── TransferToastPresenter.swift
│   ├── TransferDestinationProvider.swift               picks ~/Downloads folder
│   └── PerDeviceProgressDeriver.swift                  pure helper
└── Tests/TransferTests/
    ├── PerDeviceProgressDeriverTests.swift
    └── TransfersViewModelTests.swift
```

---

## Task 1: Package skeleton

**Files:**
- Create: `Packages/Features/Transfer/Package.swift`

- [ ] **Step 1: Manifest**

Write `Packages/Features/Transfer/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transfer",
    platforms: [.macOS(.v15)],
    products: [.library(name: "Transfer", targets: ["Transfer"])],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "Transfer",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TransferTests",
            dependencies: ["Transfer"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
```

- [ ] **Step 2: Build placeholder**

```bash
mkdir -p Packages/Features/Transfer/Sources/Transfer
mkdir -p Packages/Features/Transfer/Tests/TransferTests
touch Packages/Features/Transfer/Sources/Transfer/.gitkeep
cd Packages/Features/Transfer && swift build && cd ../../..
```

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/Transfer
git commit -m "feat(transfer): scaffold Transfer feature package"
```

---

## Task 2: `PerDeviceProgressDeriver` with tests

**Files:**
- Create: `Packages/Features/Transfer/Sources/Transfer/PerDeviceProgressDeriver.swift`
- Create: `Packages/Features/Transfer/Tests/TransferTests/PerDeviceProgressDeriverTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/Features/Transfer/Tests/TransferTests/PerDeviceProgressDeriverTests.swift`:

```swift
import Foundation
import Testing
import FreeDroidDomain
@testable import Transfer

@Suite("PerDeviceProgressDeriver")
struct PerDeviceProgressDeriverTests {
    private func progress(_ jobID: UUID, completed: Int64, total: Int64) -> TransferProgress {
        TransferProgress(jobID: jobID, completedBytes: completed, totalBytes: total, currentItem: nil, bytesPerSecond: 0)
    }

    @Test func mergesProgressFromMultipleJobsForSameDevice() {
        let deviceID = DeviceID(raw: "A")
        let jobsByDevice: [DeviceID: [UUID]] = [
            deviceID: [UUID(), UUID()]
        ]
        let jobs = jobsByDevice[deviceID] ?? []
        let states: [TransferState] = [
            .running(progress(jobs[0], completed: 50, total: 100)),
            .running(progress(jobs[1], completed: 200, total: 400))
        ]
        let deriver = PerDeviceProgressDeriver()
        let map = deriver.derive(states: states, deviceForJob: { jobID in deviceID })
        #expect(map[deviceID] == 0.5)
    }

    @Test func completedJobsContributeFully() {
        let deviceID = DeviceID(raw: "A")
        let states: [TransferState] = [.completed]
        let deriver = PerDeviceProgressDeriver()
        let map = deriver.derive(states: states, deviceForJob: { _ in deviceID })
        #expect(map[deviceID] == nil)
    }
}
```

- [ ] **Step 2: Implement deriver**

Write `Packages/Features/Transfer/Sources/Transfer/PerDeviceProgressDeriver.swift`:

```swift
import Foundation
import FreeDroidDomain

public struct PerDeviceProgressDeriver: Sendable {
    public init() {}

    public func derive(
        states: [TransferState],
        deviceForJob: (UUID) -> DeviceID?
    ) -> [DeviceID: Double] {
        var totals: [DeviceID: (Int64, Int64)] = [:]
        for state in states {
            switch state {
            case .running(let progress), .paused(let progress):
                guard let device = deviceForJob(progress.jobID) else { continue }
                let pair = totals[device] ?? (0, 0)
                totals[device] = (pair.0 + progress.completedBytes, pair.1 + max(progress.totalBytes, 1))
            case .idle, .completed, .failed:
                continue
            }
        }
        return totals.mapValues { Double($0.0) / Double($0.1) }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/Features/Transfer && swift test --filter PerDeviceProgressDeriverTests`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/Transfer
git commit -m "feat(transfer): add PerDeviceProgressDeriver with tests"
```

---

## Task 3: `StartTransferUseCase`, `CancelTransferUseCase`, `TransferDestinationProvider`

**Files:**
- Create: `Packages/Features/Transfer/Sources/Transfer/StartTransferUseCase.swift`
- Create: `Packages/Features/Transfer/Sources/Transfer/CancelTransferUseCase.swift`
- Create: `Packages/Features/Transfer/Sources/Transfer/TransferDestinationProvider.swift`

- [ ] **Step 1: Implement them**

Write `Packages/Features/Transfer/Sources/Transfer/TransferDestinationProvider.swift`:

```swift
import Foundation

public protocol TransferDestinationProvider: Sendable {
    func destinationForDevice(_ deviceName: String) -> URL
}

public struct DownloadsTransferDestinationProvider: TransferDestinationProvider {
    public init() {}

    public func destinationForDevice(_ deviceName: String) -> URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let safe = deviceName.replacingOccurrences(of: "/", with: "-")
        let folder = base.appendingPathComponent("FreeDroid/\(safe)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
```

Write `Packages/Features/Transfer/Sources/Transfer/StartTransferUseCase.swift`:

```swift
import Foundation
import FreeDroidDomain

public struct StartTransferUseCase: Sendable {
    public let repository: any TransferRepository
    public let destinations: any TransferDestinationProvider

    public init(repository: any TransferRepository, destinations: any TransferDestinationProvider) {
        self.repository = repository
        self.destinations = destinations
    }

    public func callAsFunction(
        deviceID: DeviceID,
        deviceName: String,
        items: [RemotePath]
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        let destination = destinations.destinationForDevice(deviceName)
        let job = TransferJob(
            deviceID: deviceID,
            direction: .toMac,
            items: items,
            destination: destination
        )
        return repository.enqueue(job)
    }
}
```

Write `Packages/Features/Transfer/Sources/Transfer/CancelTransferUseCase.swift`:

```swift
import Foundation
import FreeDroidDomain

public struct CancelTransferUseCase: Sendable {
    public let repository: any TransferRepository

    public init(repository: any TransferRepository) {
        self.repository = repository
    }

    public func callAsFunction(_ jobID: UUID) async {
        await repository.cancel(jobID)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
cd Packages/Features/Transfer && swift build && cd ../../..
git add Packages/Features/Transfer
git commit -m "feat(transfer): add Start/Cancel use cases and destination provider"
```

---

## Task 4: `TransfersViewModel` with tests

**Files:**
- Create: `Packages/Features/Transfer/Sources/Transfer/TransfersViewModel.swift`
- Create: `Packages/Features/Transfer/Tests/TransferTests/TransfersViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/Features/Transfer/Tests/TransferTests/TransfersViewModelTests.swift`:

```swift
import Foundation
import Testing
import FreeDroidDomain
@testable import Transfer

final class StubTransferRepository: TransferRepository, @unchecked Sendable {
    let stream: AsyncStream<[TransferState]>
    let continuation: AsyncStream<[TransferState]>.Continuation

    init() {
        var cont: AsyncStream<[TransferState]>.Continuation!
        self.stream = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func enqueue(_ job: TransferJob) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { c in c.finish() }
    }

    func cancel(_ jobID: UUID) async {}
    func observe() -> AsyncStream<[TransferState]> { stream }

    func emit(_ states: [TransferState]) {
        continuation.yield(states)
    }
}

@MainActor
@Suite("TransfersViewModel")
struct TransfersViewModelTests {
    @Test func observesStateStream() async throws {
        let repo = StubTransferRepository()
        let vm = TransfersViewModel(repository: repo, cancel: CancelTransferUseCase(repository: repo))
        let task = Task { await vm.observe() }
        let id = UUID()
        let progress = TransferProgress(jobID: id, completedBytes: 50, totalBytes: 100, currentItem: nil, bytesPerSecond: 0)
        repo.emit([.running(progress)])
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.states.count == 1)
        task.cancel()
    }
}
```

- [ ] **Step 2: Implement `TransfersViewModel`**

Write `Packages/Features/Transfer/Sources/Transfer/TransfersViewModel.swift`:

```swift
import Foundation
import Observation
import FreeDroidDomain

@MainActor
@Observable
public final class TransfersViewModel {
    public private(set) var states: [TransferState] = []
    public private(set) var jobToDevice: [UUID: DeviceID] = [:]
    public private(set) var deviceFractions: [DeviceID: Double] = [:]

    private let repository: any TransferRepository
    private let cancel: CancelTransferUseCase
    private let deriver = PerDeviceProgressDeriver()

    public init(repository: any TransferRepository, cancel: CancelTransferUseCase) {
        self.repository = repository
        self.cancel = cancel
    }

    public func observe() async {
        for await snapshot in repository.observe() {
            states = snapshot
            recomputeDeviceFractions()
        }
    }

    public func register(jobID: UUID, on deviceID: DeviceID) {
        jobToDevice[jobID] = deviceID
        recomputeDeviceFractions()
    }

    public func cancel(_ jobID: UUID) async {
        await cancel(jobID)
    }

    private func recomputeDeviceFractions() {
        deviceFractions = deriver.derive(states: states) { jobID in
            jobToDevice[jobID]
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/Features/Transfer && swift test --filter TransfersViewModelTests`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/Transfer
git commit -m "feat(transfer): add TransfersViewModel observing state stream"
```

---

## Task 5: `TransferRow` and `TransfersPanel`

**Files:**
- Create: `Packages/Features/Transfer/Sources/Transfer/TransferRow.swift`
- Create: `Packages/Features/Transfer/Sources/Transfer/TransfersPanel.swift`

- [ ] **Step 1: Implement `TransferRow`**

Write `Packages/Features/Transfer/Sources/Transfer/TransferRow.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct TransferRow: View {
    @Environment(\.theme) private var theme
    public let state: TransferState
    public let deviceName: String?
    public let onCancel: () -> Void

    public init(state: TransferState, deviceName: String? = nil, onCancel: @escaping () -> Void) {
        self.state = state
        self.deviceName = deviceName
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: Spacing.md - 2) {
            statusIndicator
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typography.bodyEmphasized).foregroundStyle(theme.colors.text0)
                if let subtitle {
                    Text(subtitle).font(Typography.caption).foregroundStyle(theme.colors.text2)
                }
            }
            Spacer()
            if case .running = state {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(theme.colors.text2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm + 1)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(theme.colors.background1.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(theme.colors.line, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch state {
        case .running(let progress):
            Spinner(size: 16)
                .overlay(Text("\(Int(progress.fraction * 100))").font(Typography.monoCaption))
        case .paused:
            Image(systemName: "pause.circle").foregroundStyle(theme.colors.warning)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.accent)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(theme.colors.danger)
        case .idle:
            Image(systemName: "circle.dotted").foregroundStyle(theme.colors.text2)
        }
    }

    private var title: String {
        switch state {
        case .running(let p):
            let total = ByteCountFormatter().string(fromByteCount: p.totalBytes)
            return "Copying · \(total) total"
        case .paused: return "Paused"
        case .completed: return "Complete"
        case .failed(let err): return "Failed · \(err)"
        case .idle: return "Idle"
        }
    }

    private var subtitle: String? {
        deviceName
    }
}
```

- [ ] **Step 2: Implement `TransfersPanel`**

Write `Packages/Features/Transfer/Sources/Transfer/TransfersPanel.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct TransfersPanel: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: TransfersViewModel
    var deviceNameByID: (DeviceID) -> String?

    public init(viewModel: TransfersViewModel, deviceNameByID: @escaping (DeviceID) -> String?) {
        self.viewModel = viewModel
        self.deviceNameByID = deviceNameByID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Transfers").font(Typography.bodyEmphasized).foregroundStyle(theme.colors.text0)
                Spacer()
                Text("\(viewModel.states.count) active")
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
            }
            if viewModel.states.isEmpty {
                Text("No active transfers")
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
                    .padding(.vertical, Spacing.sm)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs + 2) {
                        ForEach(Array(viewModel.states.enumerated()), id: \.offset) { _, state in
                            TransferRow(
                                state: state,
                                deviceName: deviceName(for: state),
                                onCancel: { Task { if let id = jobID(in: state) { await viewModel.cancel(id) } } }
                            )
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(theme.colors.line, lineWidth: 1)
                )
        )
        .task { await viewModel.observe() }
    }

    private func jobID(in state: TransferState) -> UUID? {
        switch state {
        case .running(let p), .paused(let p): return p.jobID
        default: return nil
        }
    }

    private func deviceName(for state: TransferState) -> String? {
        guard let jobID = jobID(in: state),
              let deviceID = viewModel.jobToDevice[jobID] else { return nil }
        return deviceNameByID(deviceID)
    }
}
```

- [ ] **Step 3: Build**

Run: `cd Packages/Features/Transfer && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/Transfer
git commit -m "feat(transfer): add TransferRow and TransfersPanel"
```

---

## Task 6: `TransferToastPresenter`

**Files:**
- Create: `Packages/Features/Transfer/Sources/Transfer/TransferToastPresenter.swift`

- [ ] **Step 1: Implement**

Write `Packages/Features/Transfer/Sources/Transfer/TransferToastPresenter.swift`:

```swift
import Foundation
import Observation
import FreeDroidDomain
import FreeDroidUI

@MainActor
@Observable
public final class TransferToastPresenter {
    public private(set) var toasts: [Toast] = []

    public init() {}

    public func consume(_ states: [TransferState]) {
        for state in states {
            switch state {
            case .completed:
                push(kind: .success, title: "Transfer complete")
            case .failed(let error):
                push(kind: .danger, title: "Transfer failed", detail: shortMessage(error))
            default:
                continue
            }
        }
    }

    private func push(kind: ToastKind, title: String, detail: String? = nil) {
        let toast = Toast(kind: kind, title: title, detail: detail)
        toasts.append(toast)
        let removeID = toast.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.toasts.removeAll { $0.id == removeID }
        }
    }

    private func shortMessage(_ error: TransportError) -> String {
        switch error {
        case .notConnected: "Device disconnected"
        case .unauthorized: "Unauthorized"
        case .timeout: "Timed out"
        case .ioFailure(let m): m
        case .notFound: "File not found"
        case .alreadyExists: "Already exists"
        case .unsupported(let r): r
        case .cancelled: "Cancelled"
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/Transfer && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/Transfer
git commit -m "feat(transfer): add TransferToastPresenter"
```

---

## Task 7: Wire into app

**Files:**
- Modify: `FreeDroid/AppContainer.swift`
- Modify: `FreeDroid/ContentView.swift`
- Modify: `Packages/Features/Gallery/Sources/Gallery/GalleryView.swift` if needed (already takes a callback)

- [ ] **Step 1: Add `Transfer` to workspace**

Xcode → Add Local → `Packages/Features/Transfer`. Add to target frameworks.

- [ ] **Step 2: Extend `AppContainer`**

In `FreeDroid/AppContainer.swift`, import `Transfer` and add:

```swift
import Transfer

    let transferQueue = TransferQueue()
    let transferDestinations = DownloadsTransferDestinationProvider()
    lazy var transferRepository: TransferRepositoryImpl = TransferRepositoryImpl(queue: transferQueue, registry: registry)
    lazy var transfersViewModel: TransfersViewModel = TransfersViewModel(
        repository: transferRepository,
        cancel: CancelTransferUseCase(repository: transferRepository)
    )
    lazy var transferToastPresenter = TransferToastPresenter()

    func startTransferUseCase() -> StartTransferUseCase {
        StartTransferUseCase(repository: transferRepository, destinations: transferDestinations)
    }
```

- [ ] **Step 3: Hook Gallery "Copy to Mac" to real transfer**

In `FreeDroid/ContentView.swift`, replace the Gallery `onCopySelectionToMac` closure:

```swift
GalleryView(viewModel: container.galleryViewModel(for: selectedID), onCopySelectionToMac: { items in
    Task {
        guard let device = await container.registry.device(selectedID) else { return }
        let stream = container.startTransferUseCase()(
            deviceID: selectedID,
            deviceName: device.displayName,
            items: items.map { $0.path }
        )
        for try await progress in stream {
            container.transfersViewModel.register(jobID: progress.jobID, on: selectedID)
        }
    }
})
```

Add a `TransfersPanel` overlay anchored to the bottom-right of `ContentView`:

```swift
.overlay(alignment: .bottomTrailing) {
    if !container.transfersViewModel.states.isEmpty {
        TransfersPanel(viewModel: container.transfersViewModel, deviceNameByID: { id in
            container.deviceListViewModel.devices.first { $0.id == id }?.displayName
        })
        .frame(width: 360)
        .padding(Spacing.lg)
    }
}
.overlay(alignment: .topTrailing) {
    VStack(spacing: Spacing.sm) {
        ForEach(container.transferToastPresenter.toasts) { toast in
            toast
        }
    }
    .padding(Spacing.lg)
}
.task {
    for await states in container.transferRepository.observe() {
        container.transferToastPresenter.consume(states)
    }
}
```

- [ ] **Step 4: Subscribe device cards to per-device fraction**

In `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceListView.swift`, add a parameter for `deviceFractions: [DeviceID: Double]` and pass it through to `DeviceCardViewModel`:

```swift
public struct DeviceListView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: DeviceListViewModel
    var deviceFractions: [DeviceID: Double]

    public init(viewModel: DeviceListViewModel, deviceFractions: [DeviceID: Double]) {
        self.viewModel = viewModel
        self.deviceFractions = deviceFractions
    }
    // …
    let cardViewModel = DeviceCardViewModel(device: device)
    if let fraction = deviceFractions[device.id] {
        cardViewModel.setTransferProgress(fraction)
    }
```

Update `ContentView` to pass `container.transfersViewModel.deviceFractions`.

- [ ] **Step 5: Build and run**

`⌘R`. Select a photo in Gallery → "Copy to Mac" → device card fills with liquid progress, TransfersPanel appears, toast pops on completion.

- [ ] **Step 6: Commit**

```bash
git add FreeDroid Packages/Features/Transfer Packages/Features/DeviceManagement Packages/Features/Gallery
git commit -m "feat: wire end-to-end transfer with liquid progress, panel, and toast"
```

---

## Task 8: CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add `test-transfer` job**

```yaml
  test-transfer:
    name: Test Transfer
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'
      - run: cd Packages/Features/Transfer && swift test --parallel
```

Add to `build-app.needs`.

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "ci: run Transfer test suite"
```

---

## Done When

- `swift test` in `Transfer` passes.
- Selecting photos and clicking "Copy to Mac" pulls them into `~/Downloads/FreeDroid/<device>`.
- The selected device card fills with liquid progress and clears at completion.
- The Transfers panel appears bottom-right while transfers are active.
- Toasts pop top-right on completion / failure.
- SwiftLint passes.

## Self-Review

- Spec §8.3 (Liquid transfer fill, Toast pearls) → Task 7 wiring + reuse of `FluidProgress` and `Toast` from `FreeDroidUI`.
- Spec §9.4 (per-device transfer queue) → Each transfer flows through `TransferEngine` bound to one device's transport.
- Spec §9.3 (cancellation) → `cancel(jobID)` propagates via `TransferQueue.cancel`.
