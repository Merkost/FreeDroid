# FreeDroid Plan #6 — Device Management Feature

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `DeviceManagement` feature package: SwiftUI sidebar of device cards backed by `DeviceRepository`, ADB Trust prompt sheet, transport pin preferences UI, and the empty-state for no-devices. Wire it into the app so the device list updates in real time.

**Architecture:** Feature package depends on `FreeDroidDomain` (protocols) and `FreeDroidUI` (components). Views and ViewModels live here. Repository implementations come from `FreeDroidData` and are injected at composition time. `@Observable` ViewModels expose state; views observe via `@Bindable`/`@Observable` macros.

**Tech Stack:** SwiftUI, FreeDroidDomain, FreeDroidUI, FreeDroidData (injected at composition root).

---

## File Structure

```
Packages/Features/DeviceManagement/
├── Package.swift                                       create
├── Sources/DeviceManagement/
│   ├── DeviceListViewModel.swift                       @Observable
│   ├── DeviceListView.swift                            sidebar
│   ├── DeviceCardView.swift                            single device row
│   ├── DeviceCardViewModel.swift                       @Observable per-card
│   ├── TrustPromptViewModel.swift                      @Observable
│   ├── TrustPromptSheet.swift                          SwiftUI sheet
│   ├── DeviceEmptyState.swift                          “Plug in your Android” empty state
│   ├── PinTransportPicker.swift                        in settings
│   └── ObserveTrustStatusUseCase.swift                 wraps ADBAuthorizationObserver
└── Tests/DeviceManagementTests/
    ├── DeviceListViewModelTests.swift
    └── DeviceCardViewModelTests.swift
```

---

## Task 1: Package skeleton

**Files:**
- Create: `Packages/Features/DeviceManagement/Package.swift`

- [ ] **Step 1: Write the manifest**

Write `Packages/Features/DeviceManagement/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeviceManagement",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DeviceManagement", targets: ["DeviceManagement"])
    ],
    dependencies: [
        .package(path: "../../FreeDroidDomain"),
        .package(path: "../../FreeDroidUI")
    ],
    targets: [
        .target(
            name: "DeviceManagement",
            dependencies: ["FreeDroidDomain", "FreeDroidUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DeviceManagementTests",
            dependencies: ["DeviceManagement"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
```

- [ ] **Step 2: Create directories and gitkeeps**

```bash
mkdir -p Packages/Features/DeviceManagement/Sources/DeviceManagement
mkdir -p Packages/Features/DeviceManagement/Tests/DeviceManagementTests
touch Packages/Features/DeviceManagement/Sources/DeviceManagement/.gitkeep
```

- [ ] **Step 3: Build**

Run: `cd Packages/Features/DeviceManagement && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/Features
git commit -m "feat(device-mgmt): scaffold DeviceManagement feature package"
```

---

## Task 2: `DeviceListViewModel` with tests

**Files:**
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceListViewModel.swift`
- Create: `Packages/Features/DeviceManagement/Tests/DeviceManagementTests/DeviceListViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `Packages/Features/DeviceManagement/Tests/DeviceManagementTests/DeviceListViewModelTests.swift`:

```swift
import Foundation
import Testing
import FreeDroidDomain
@testable import DeviceManagement

@MainActor
@Suite("DeviceListViewModel")
struct DeviceListViewModelTests {
    private func device(_ name: String, transport: TransportKind = .adb) -> Device {
        Device(
            id: DeviceID(raw: name),
            displayName: name,
            manufacturer: "Test",
            model: name,
            storageCapacityBytes: nil,
            storageFreeBytes: nil,
            transport: transport
        )
    }

    @Test func emptyAtFirst() {
        let vm = DeviceListViewModel(repository: StubDeviceRepository(initial: []))
        #expect(vm.devices.isEmpty)
        #expect(vm.selectedID == nil)
    }

    @Test func selectsFirstWhenDevicesAppear() async throws {
        let repo = StubDeviceRepository(initial: [])
        let vm = DeviceListViewModel(repository: repo)
        let task = Task { await vm.observe() }
        repo.emit([device("A")])
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.devices.count == 1)
        #expect(vm.selectedID == DeviceID(raw: "A"))
        task.cancel()
    }

    @Test func preservesSelectionAcrossUpdates() async throws {
        let repo = StubDeviceRepository(initial: [device("A"), device("B")])
        let vm = DeviceListViewModel(repository: repo)
        let task = Task { await vm.observe() }
        try await Task.sleep(for: .milliseconds(50))
        vm.select(DeviceID(raw: "B"))
        repo.emit([device("B"), device("C")])
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.selectedID == DeviceID(raw: "B"))
        task.cancel()
    }
}

final class StubDeviceRepository: DeviceRepository, @unchecked Sendable {
    private let continuation: AsyncStream<[Device]>.Continuation
    private let stream: AsyncStream<[Device]>
    private var devices: [Device]

    init(initial: [Device]) {
        var cont: AsyncStream<[Device]>.Continuation!
        self.stream = AsyncStream { c in cont = c }
        self.continuation = cont
        self.devices = initial
        cont.yield(initial)
    }

    func observe() -> AsyncStream<[Device]> { stream }
    func device(_ id: DeviceID) async -> Device? { devices.first { $0.id == id } }

    func emit(_ snapshot: [Device]) {
        devices = snapshot
        continuation.yield(snapshot)
    }
}
```

- [ ] **Step 2: Implement `DeviceListViewModel`**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceListViewModel.swift`:

```swift
import Foundation
import Observation
import FreeDroidDomain

@MainActor
@Observable
public final class DeviceListViewModel {
    public private(set) var devices: [Device] = []
    public var selectedID: DeviceID?
    private let repository: any DeviceRepository

    public init(repository: any DeviceRepository) {
        self.repository = repository
    }

    public func observe() async {
        for await snapshot in repository.observe() {
            apply(snapshot)
        }
    }

    public func select(_ id: DeviceID) {
        guard devices.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    private func apply(_ snapshot: [Device]) {
        devices = snapshot
        if let current = selectedID, devices.contains(where: { $0.id == current }) {
            return
        }
        selectedID = snapshot.first?.id
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/Features/DeviceManagement && swift test --filter DeviceListViewModelTests`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/DeviceManagement
git commit -m "feat(device-mgmt): add DeviceListViewModel with tests"
```

---

## Task 3: `DeviceCardViewModel` with tests

**Files:**
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceCardViewModel.swift`
- Create: `Packages/Features/DeviceManagement/Tests/DeviceManagementTests/DeviceCardViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/Features/DeviceManagement/Tests/DeviceManagementTests/DeviceCardViewModelTests.swift`:

```swift
import Foundation
import Testing
import FreeDroidDomain
import FreeDroidUI
@testable import DeviceManagement

@MainActor
@Suite("DeviceCardViewModel")
struct DeviceCardViewModelTests {
    private func device(_ id: String, transport: TransportKind) -> Device {
        Device(
            id: DeviceID(raw: id),
            displayName: id,
            manufacturer: "T",
            model: id,
            storageCapacityBytes: nil,
            storageFreeBytes: nil,
            transport: transport
        )
    }

    @Test func glyphIsFirstLetter() {
        let vm = DeviceCardViewModel(device: device("Pixel", transport: .adb))
        #expect(vm.glyph == "P")
    }

    @Test func subtitleHasTransportBadge() {
        let vm = DeviceCardViewModel(device: device("Galaxy", transport: .mtp))
        #expect(vm.transportLabel == "MTP")
        #expect(vm.transportKind == .mtp)
    }

    @Test func ringStateIdleByDefault() {
        let vm = DeviceCardViewModel(device: device("X", transport: .adb))
        #expect(vm.ringState == .idle)
    }

    @Test func ringStateTransferringWhenActive() {
        let vm = DeviceCardViewModel(device: device("X", transport: .adb))
        vm.setTransferProgress(0.3)
        #expect(vm.ringState == .transferring)
        vm.clearTransferProgress()
        #expect(vm.ringState == .idle)
    }
}
```

- [ ] **Step 2: Implement `DeviceCardViewModel`**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceCardViewModel.swift`:

```swift
import Foundation
import Observation
import FreeDroidDomain
import FreeDroidUI

@MainActor
@Observable
public final class DeviceCardViewModel: Identifiable {
    public let device: Device
    public var transferFraction: Double?

    public init(device: Device) {
        self.device = device
    }

    public var id: DeviceID { device.id }
    public var name: String { device.displayName }
    public var glyph: String { String(name.first ?? "•") }

    public var transportKind: IconChipKind {
        switch device.transport {
        case .adb: .adb
        case .mtp: .mtp
        case .wifi: .wifi
        }
    }

    public var transportLabel: String {
        switch device.transport {
        case .adb: "ADB"
        case .mtp: "MTP"
        case .wifi: "WI-FI"
        }
    }

    public var ringState: LivingRingState {
        transferFraction == nil ? .idle : .transferring
    }

    public var capacityDescription: String? {
        guard let capacity = device.storageCapacityBytes else { return nil }
        return ByteCountFormatter().string(fromByteCount: capacity)
    }

    public func setTransferProgress(_ fraction: Double) {
        transferFraction = max(0, min(1, fraction))
    }

    public func clearTransferProgress() {
        transferFraction = nil
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/Features/DeviceManagement && swift test --filter DeviceCardViewModelTests`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/DeviceManagement
git commit -m "feat(device-mgmt): add DeviceCardViewModel with tests"
```

---

## Task 4: `DeviceCardView` SwiftUI component

**Files:**
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceCardView.swift`

- [ ] **Step 1: Implement `DeviceCardView`**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceCardView.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct DeviceCardView: View {
    @Environment(\.theme) private var theme
    private let viewModel: DeviceCardViewModel
    private let isSelected: Bool

    public init(viewModel: DeviceCardViewModel, isSelected: Bool) {
        self.viewModel = viewModel
        self.isSelected = isSelected
    }

    public var body: some View {
        Card(isActive: isSelected) {
            ZStack(alignment: .bottom) {
                if let fraction = viewModel.transferFraction {
                    FluidProgress(fraction: fraction)
                }
                HStack(spacing: Spacing.md - 1) {
                    LivingRing(color: color, state: viewModel.ringState, glyph: viewModel.glyph)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.name)
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(theme.colors.text0)
                            .lineLimit(1)
                        HStack(spacing: Spacing.xs + 2) {
                            if let capacity = viewModel.capacityDescription {
                                Text(capacity)
                                    .font(Typography.caption)
                                    .foregroundStyle(theme.colors.text2)
                            }
                            IconChip(viewModel.transportLabel, kind: viewModel.transportKind)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.xs + 2)
            }
        }
    }

    private var color: Color {
        switch viewModel.transportKind {
        case .adb: theme.colors.adb
        case .mtp: theme.colors.mtp
        case .wifi: theme.colors.wifi
        case .off: theme.colors.text2
        case .custom(let c): c
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/DeviceManagement && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/DeviceManagement
git commit -m "feat(device-mgmt): add DeviceCardView"
```

---

## Task 5: `DeviceListView` sidebar and `DeviceEmptyState`

**Files:**
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceEmptyState.swift`
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceListView.swift`

- [ ] **Step 1: Implement `DeviceEmptyState`**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceEmptyState.swift`:

```swift
import SwiftUI
import FreeDroidUI

public struct DeviceEmptyState: View {
    public init() {}

    public var body: some View {
        EmptyState(
            icon: "cable.connector",
            title: "No devices found",
            message: "Plug in your Android phone with a USB cable. We'll detect it automatically."
        )
    }
}
```

- [ ] **Step 2: Implement `DeviceListView`**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/DeviceListView.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct DeviceListView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: DeviceListViewModel

    public init(viewModel: DeviceListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Devices")
                .font(Typography.label)
                .foregroundStyle(theme.colors.text2)
                .padding(.horizontal, Spacing.sm + 2)
                .padding(.top, Spacing.lg)
            ScrollView {
                LazyVStack(spacing: Spacing.xs + 2) {
                    if viewModel.devices.isEmpty {
                        DeviceEmptyState()
                    } else {
                        ForEach(viewModel.devices) { device in
                            let cardViewModel = DeviceCardViewModel(device: device)
                            DeviceCardView(viewModel: cardViewModel, isSelected: device.id == viewModel.selectedID)
                                .onTapGesture { viewModel.select(device.id) }
                                .motion(.crisp, value: viewModel.selectedID)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm + 2)
            }
        }
        .frame(width: 280)
        .background(.regularMaterial)
        .task {
            await viewModel.observe()
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `cd Packages/Features/DeviceManagement && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/Features/DeviceManagement
git commit -m "feat(device-mgmt): add DeviceListView sidebar and empty state"
```

---

## Task 6: `TrustPromptViewModel` and `TrustPromptSheet`

**Files:**
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/ObserveTrustStatusUseCase.swift`
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/TrustPromptViewModel.swift`
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/TrustPromptSheet.swift`

- [ ] **Step 1: Domain protocol for trust observer**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/ObserveTrustStatusUseCase.swift`:

```swift
public enum TrustStatus: Sendable, Hashable {
    case waiting
    case authorized
    case missing
    case error(String)
}

public protocol ObserveTrustStatusUseCase: Sendable {
    func callAsFunction(serial: String) -> AsyncStream<TrustStatus>
}
```

- [ ] **Step 2: Implement `TrustPromptViewModel`**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/TrustPromptViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class TrustPromptViewModel {
    public private(set) var status: TrustStatus = .waiting
    public let serial: String
    private let observe: any ObserveTrustStatusUseCase
    private var task: Task<Void, Never>?

    public init(serial: String, observe: any ObserveTrustStatusUseCase) {
        self.serial = serial
        self.observe = observe
    }

    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            for await change in self.observe(serial: self.serial) {
                await MainActor.run {
                    self.status = change
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public var isWaiting: Bool { status == .waiting }
    public var isAuthorized: Bool { status == .authorized }
}
```

- [ ] **Step 3: Implement `TrustPromptSheet`**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/TrustPromptSheet.swift`:

```swift
import SwiftUI
import FreeDroidUI

public struct TrustPromptSheet: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: TrustPromptViewModel
    var onDismiss: () -> Void

    public init(viewModel: TrustPromptViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Sheet {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(theme.colors.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trust this Mac").font(Typography.title)
                        Text("Check your phone — tap Allow to authorize USB debugging.")
                            .font(Typography.body)
                            .foregroundStyle(theme.colors.text1)
                    }
                }
                Divider().overlay(theme.colors.line)
                statusRow
                HStack {
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                    if viewModel.isAuthorized {
                        Button("Continue", action: onDismiss)
                            .buttonStyle(.borderedProminent)
                            .tint(theme.colors.accent)
                    }
                }
            }
        }
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: Spacing.sm + 2) {
            switch viewModel.status {
            case .waiting:
                Spinner()
                Text("Waiting for your phone…").font(Typography.body)
            case .authorized:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.accent)
                Text("Authorized").font(Typography.body)
            case .missing:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.colors.warning)
                Text("Device disconnected. Reconnect to retry.").font(Typography.body)
            case .error(let message):
                Image(systemName: "xmark.octagon").foregroundStyle(theme.colors.danger)
                Text(message).font(Typography.body)
            }
        }
    }
}
```

- [ ] **Step 4: Build**

Run: `cd Packages/Features/DeviceManagement && swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Packages/Features/DeviceManagement
git commit -m "feat(device-mgmt): add Trust prompt sheet and view model"
```

---

## Task 7: `PinTransportPicker`

**Files:**
- Create: `Packages/Features/DeviceManagement/Sources/DeviceManagement/PinTransportPicker.swift`

- [ ] **Step 1: Implement the picker**

Write `Packages/Features/DeviceManagement/Sources/DeviceManagement/PinTransportPicker.swift`:

```swift
import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct PinTransportPicker: View {
    @Environment(\.theme) private var theme
    @Binding var selection: TransportKind?
    var availableTransports: Set<TransportKind>

    public init(selection: Binding<TransportKind?>, availableTransports: Set<TransportKind>) {
        self._selection = selection
        self.availableTransports = availableTransports
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Preferred transport").font(Typography.label).foregroundStyle(theme.colors.text2)
            HStack(spacing: Spacing.xs + 2) {
                option(.adb, label: "ADB")
                option(.mtp, label: "MTP")
                autoOption
            }
        }
    }

    @ViewBuilder
    private func option(_ kind: TransportKind, label: String) -> some View {
        Button {
            selection = selection == kind ? nil : kind
        } label: {
            HStack(spacing: 4) {
                IconChip(label, kind: chipKind(for: kind))
                if selection == kind {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selection == kind ? theme.colors.accentSoft : theme.colors.background1.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!availableTransports.contains(kind))
        .opacity(availableTransports.contains(kind) ? 1.0 : 0.4)
    }

    private var autoOption: some View {
        Button {
            selection = nil
        } label: {
            Text("Auto")
                .font(Typography.captionEmphasized)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(selection == nil ? theme.colors.accentSoft : theme.colors.background1.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
    }

    private func chipKind(for kind: TransportKind) -> IconChipKind {
        switch kind {
        case .adb: .adb
        case .mtp: .mtp
        case .wifi: .wifi
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/Features/DeviceManagement && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/Features/DeviceManagement
git commit -m "feat(device-mgmt): add PinTransportPicker for preferred transport selection"
```

---

## Task 8: Wire `DeviceListView` into the app

**Files:**
- Modify: `FreeDroid/AppContainer.swift`
- Modify: `FreeDroid/ContentView.swift`
- Modify: `FreeDroid.xcodeproj/project.pbxproj` (via Xcode add packages UI)

- [ ] **Step 1: Add the new packages to the workspace**

In Xcode → File → Add Package Dependencies → Add Local:
- `Packages/FreeDroidData`
- `Packages/FreeDroidADB`
- `Packages/FreeDroidMTP`
- `Packages/Features/DeviceManagement`

Then in `FreeDroid` target → Frameworks, Libraries, and Embedded Content, add `DeviceManagement`, `FreeDroidData`, `FreeDroidADB`, `FreeDroidMTP`.

- [ ] **Step 2: Update `AppContainer.swift`**

Overwrite `FreeDroid/AppContainer.swift`:

```swift
import Foundation
import Observation
import FreeDroidDomain
import FreeDroidData
import FreeDroidADB
import FreeDroidMTP
import DeviceManagement

@MainActor
@Observable
final class AppContainer {
    let bundleVersion: String

    let adbServer: ADBServer
    let mtpRuntime = MTPRuntime()
    let mtpDiscovery: MTPDeviceDiscovery
    let pinPreference = DevicePinPreference()
    let listingCache = ListingCache()
    let thumbnailCache: ThumbnailCache
    let registry: DeviceRegistry
    let deviceRepository: DeviceRepositoryImpl
    let deviceListViewModel: DeviceListViewModel

    init() {
        self.bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let adbServer = try! ADBServer.liveSync()
        self.adbServer = adbServer
        self.mtpDiscovery = MTPDeviceDiscovery(runtime: mtpRuntime)
        let thumbsURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeDroid/thumbs", isDirectory: true)
        self.thumbnailCache = ThumbnailCache(rootURL: thumbsURL)
        self.registry = DeviceRegistry(
            adbServer: adbServer,
            mtpRuntime: mtpRuntime,
            mtpDiscovery: mtpDiscovery,
            pinPreference: pinPreference
        )
        self.deviceRepository = DeviceRepositoryImpl(registry: registry)
        self.deviceListViewModel = DeviceListViewModel(repository: deviceRepository)
    }

    func start() async {
        try? await registry.start()
    }
}
```

> `ADBServer.liveSync()` does not exist yet — add it to `FreeDroidADB`:

In `Packages/FreeDroidADB/Sources/FreeDroidADB/ADBServer.swift`, add:

```swift
public extension ADBServer {
    static func liveSync(port: Int = 5037) throws -> ADBServer {
        let binary = try ADBBinary.path()
        return ADBServer(runner: LiveADBRunner(binary: binary, port: port))
    }
}
```

- [ ] **Step 3: Update `ContentView.swift`**

Overwrite `FreeDroid/ContentView.swift`:

```swift
import SwiftUI
import FreeDroidUI
import DeviceManagement

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @State private var theme: Theme = .dark

    var body: some View {
        ZStack {
            AmbientGradientBackground().ignoresSafeArea()
            HStack(spacing: 0) {
                DeviceListView(viewModel: container.deviceListViewModel)
                Divider().overlay(theme.colors.line)
                placeholderDetail
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .freeDroidTheme(theme)
        .task { await container.start() }
    }

    private var placeholderDetail: some View {
        ZStack {
            Color.clear
            VStack(spacing: Spacing.md) {
                Text("Select a device").font(Typography.title)
                Text("Plug in a phone or pick one from the sidebar to start browsing.")
                    .font(Typography.body)
                    .foregroundStyle(theme.colors.text2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Build and run**

`⌘R` in Xcode.
Expected: a window with the sidebar on the left. With no device plugged in, the empty state shows; with an Android phone plugged in and authorized, the device card appears.

- [ ] **Step 5: Commit**

```bash
git add FreeDroid Packages/FreeDroidADB Packages/Features
git commit -m "feat: integrate device list sidebar with live transport orchestration"
```

---

## Task 9: Update CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add `test-device-mgmt` job**

In `.github/workflows/ci.yml`, after `test-data`:

```yaml
  test-device-mgmt:
    name: Test DeviceManagement
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'
      - name: Build & test
        run: |
          cd Packages/Features/DeviceManagement
          swift test --parallel
```

Add to `build-app.needs`.

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "ci: run DeviceManagement test suite"
```

---

## Done When

- `swift test` in `DeviceManagement` passes.
- The app launches and shows the sidebar.
- Plugging in an Android device causes a card to appear within a few seconds.
- Unplugging the device removes the card.
- Selecting a card highlights it and updates `selectedID`.
- An unauthorized ADB device surfaces a Trust prompt sheet (manual integration verification).
- SwiftLint passes.

## Self-Review

- Spec §8.3 (Living device ring, Liquid transfer fill) → Tasks 4 (`LivingRing` + `FluidProgress` integrated in `DeviceCardView`).
- Spec §6.3 (auto-selection) → `DeviceRegistry` from Plan #5 selects transport; this plan honors and displays it.
- Spec §6.1 (Trust prompt) → Task 6.
- Spec §4.2 (Clean Architecture) → ViewModels depend only on Domain protocols; concrete impls injected at composition root.
