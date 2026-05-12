# FreeDroid Plan #10 — FSKit Extension

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `FreeDroidFS.fskitmodule` extension target plus the `FreeDroidIPC` package that carries XPC types between the app and the extension. End result: plugging an authorized Android phone makes a real volume appear in Finder under `/Volumes/<Device Name>`. Reading, writing, listing, renaming, deleting, and creating folders all route through the FSKit extension → XPC → the app's `Transport`.

**Architecture:** Two new artifacts. `FreeDroidIPC` is a Swift Package with Codable XPC request/response types — shared imports for app and extension. `FreeDroidFS.fskitmodule` is an Xcode extension target with `com.apple.developer.fskit.fsmodule` entitlement. The extension implements `FSUnaryFileSystem` / `FSVolume` / `FSItem` types, translating calls into XPC messages to a Mach service hosted in the main app. The app implements `XPCFileServer` (an `NSXPCListenerDelegate`) and registers itself with `FSFileSystemManager` per attached device.

**Tech Stack:** Swift 6, FSKit (macOS 15.4+), XPC via `NSXPCConnection`, FreeDroidDomain, FreeDroidData.

---

## File Structure

```
Packages/FreeDroidIPC/
├── Package.swift                                       create
└── Sources/FreeDroidIPC/
    ├── IPCRequest.swift
    ├── IPCResponse.swift
    ├── IPCError.swift
    ├── IPCEndpoint.swift                                Mach service name constants
    └── IPCEncoder.swift                                 JSONEncoder/Decoder helpers

FreeDroid/
├── IPC/
│   ├── XPCFileServer.swift                              app-side listener
│   ├── XPCConnectionRegistry.swift                      one listener per device
│   └── XPCFileServerHandler.swift                       maps requests → transports

FreeDroidFS/                                              new extension target (Xcode)
├── Info.plist
├── FreeDroidFS.entitlements
├── FreeDroidFSModule.swift                              FSUnaryFileSystem
├── FreeDroidVolume.swift                                FSVolume
├── FreeDroidItem.swift                                  FSItem subclass
├── XPCClient.swift                                      extension-side client
└── ErrnoMapping.swift                                   TransportError → POSIX
```

---

## Task 1: `FreeDroidIPC` package

**Files:**
- Create: `Packages/FreeDroidIPC/Package.swift`
- Create: `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCRequest.swift`
- Create: `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCResponse.swift`
- Create: `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCError.swift`
- Create: `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCEndpoint.swift`
- Create: `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCEncoder.swift`

- [ ] **Step 1: Manifest**

Write `Packages/FreeDroidIPC/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeDroidIPC",
    platforms: [.macOS(.v15)],
    products: [.library(name: "FreeDroidIPC", targets: ["FreeDroidIPC"])],
    dependencies: [.package(path: "../FreeDroidDomain")],
    targets: [
        .target(
            name: "FreeDroidIPC",
            dependencies: ["FreeDroidDomain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
```

- [ ] **Step 2: Implement IPC types**

Write `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCEndpoint.swift`:

```swift
public enum IPCEndpoint {
    public static let machServiceName = "com.merkost.freedroid.XPCFileServer"
}
```

Write `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCRequest.swift`:

```swift
import Foundation
import FreeDroidDomain

public enum IPCRequest: Codable, Sendable {
    case list(deviceID: DeviceID, path: RemotePath)
    case stat(deviceID: DeviceID, path: RemotePath)
    case read(deviceID: DeviceID, path: RemotePath, offset: Int64, length: Int)
    case write(deviceID: DeviceID, path: RemotePath, data: Data, offset: Int64)
    case mkdir(deviceID: DeviceID, path: RemotePath)
    case remove(deviceID: DeviceID, path: RemotePath)
    case rename(deviceID: DeviceID, from: RemotePath, to: RemotePath)
}
```

Write `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCResponse.swift`:

```swift
import Foundation
import FreeDroidDomain

public enum IPCResponse: Codable, Sendable {
    case entries([RemoteEntry])
    case entry(RemoteEntry)
    case data(Data)
    case empty
    case failure(IPCError)
}
```

Write `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCError.swift`:

```swift
import FreeDroidDomain

public enum IPCError: Codable, Sendable, Equatable {
    case transport(TransportError)
    case noTransport
    case decodingFailed(String)
}

extension TransportError: Codable {
    enum CodingKeys: String, CodingKey { case kind, payload }
    enum Kind: String, Codable { case notConnected, unauthorized, timeout, ioFailure, notFound, alreadyExists, unsupported, cancelled }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .notConnected: self = .notConnected
        case .unauthorized: self = .unauthorized
        case .timeout:
            let seconds = try container.decode(Double.self, forKey: .payload)
            self = .timeout(.seconds(seconds))
        case .ioFailure:
            let message = try container.decode(String.self, forKey: .payload)
            self = .ioFailure(message: message)
        case .notFound:
            let path = try container.decode(RemotePath.self, forKey: .payload)
            self = .notFound(path)
        case .alreadyExists:
            let path = try container.decode(RemotePath.self, forKey: .payload)
            self = .alreadyExists(path)
        case .unsupported:
            let reason = try container.decode(String.self, forKey: .payload)
            self = .unsupported(reason: reason)
        case .cancelled: self = .cancelled
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notConnected: try container.encode(Kind.notConnected, forKey: .kind)
        case .unauthorized: try container.encode(Kind.unauthorized, forKey: .kind)
        case .timeout(let d):
            try container.encode(Kind.timeout, forKey: .kind)
            try container.encode(d.components.seconds + Double(d.components.attoseconds) / 1e18, forKey: .payload)
        case .ioFailure(let m):
            try container.encode(Kind.ioFailure, forKey: .kind)
            try container.encode(m, forKey: .payload)
        case .notFound(let p):
            try container.encode(Kind.notFound, forKey: .kind)
            try container.encode(p, forKey: .payload)
        case .alreadyExists(let p):
            try container.encode(Kind.alreadyExists, forKey: .kind)
            try container.encode(p, forKey: .payload)
        case .unsupported(let r):
            try container.encode(Kind.unsupported, forKey: .kind)
            try container.encode(r, forKey: .payload)
        case .cancelled: try container.encode(Kind.cancelled, forKey: .kind)
        }
    }
}
```

Write `Packages/FreeDroidIPC/Sources/FreeDroidIPC/IPCEncoder.swift`:

```swift
import Foundation

public enum IPCCoder {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.dataEncodingStrategy = .base64
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.dataDecodingStrategy = .base64
        return d
    }()
}
```

- [ ] **Step 3: Build**

Run: `cd Packages/FreeDroidIPC && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/FreeDroidIPC
git commit -m "feat(ipc): add FreeDroidIPC package with Codable XPC types"
```

---

## Task 2: App-side `XPCFileServer`

**Files:**
- Create: `FreeDroid/IPC/XPCFileServer.swift`
- Create: `FreeDroid/IPC/XPCFileServerHandler.swift`
- Create: `FreeDroid/IPC/XPCConnectionRegistry.swift`

- [ ] **Step 1: Add `FreeDroidIPC` to the workspace and `FreeDroid` target**

In Xcode: Add Local Package → `Packages/FreeDroidIPC` → add to `FreeDroid` target.

- [ ] **Step 2: Define the protocol exposed over XPC**

Write `FreeDroid/IPC/XPCFileServer.swift`:

```swift
import Foundation
import FreeDroidIPC

@objc protocol XPCFileServerProtocol {
    func send(_ payload: Data) async -> Data
}

final class XPCFileServer: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let handler: XPCFileServerHandler

    init(handler: XPCFileServerHandler) {
        self.handler = handler
        self.listener = NSXPCListener(machServiceName: IPCEndpoint.machServiceName)
        super.init()
        self.listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
        newConnection.exportedObject = XPCFileServerExportedObject(handler: handler)
        newConnection.resume()
        return true
    }
}

final class XPCFileServerExportedObject: NSObject, XPCFileServerProtocol {
    private let handler: XPCFileServerHandler

    init(handler: XPCFileServerHandler) {
        self.handler = handler
    }

    func send(_ payload: Data) async -> Data {
        await handler.handle(payload: payload)
    }
}
```

- [ ] **Step 3: Implement the handler**

Write `FreeDroid/IPC/XPCFileServerHandler.swift`:

```swift
import Foundation
import FreeDroidDomain
import FreeDroidData
import FreeDroidIPC

actor XPCFileServerHandler {
    private let registry: DeviceRegistry

    init(registry: DeviceRegistry) {
        self.registry = registry
    }

    func handle(payload: Data) async -> Data {
        do {
            let request = try IPCCoder.decoder.decode(IPCRequest.self, from: payload)
            let response = try await execute(request)
            return try IPCCoder.encoder.encode(response)
        } catch let error as TransportError {
            let response = IPCResponse.failure(.transport(error))
            return (try? IPCCoder.encoder.encode(response)) ?? Data()
        } catch {
            let response = IPCResponse.failure(.decodingFailed(String(describing: error)))
            return (try? IPCCoder.encoder.encode(response)) ?? Data()
        }
    }

    private func transport(for id: DeviceID) async throws -> any Transport {
        guard let t = await registry.transport(for: id) else { throw TransportError.notConnected }
        return t
    }

    private func execute(_ request: IPCRequest) async throws -> IPCResponse {
        switch request {
        case let .list(deviceID, path):
            return .entries(try await transport(for: deviceID).list(path))
        case let .stat(deviceID, path):
            return .entry(try await transport(for: deviceID).stat(path))
        case let .read(deviceID, path, offset, length):
            return .data(try await transport(for: deviceID).read(path, offset: offset, length: length))
        case let .write(deviceID, path, data, offset):
            try await transport(for: deviceID).write(path, data: data, offset: offset)
            return .empty
        case let .mkdir(deviceID, path):
            try await transport(for: deviceID).mkdir(path)
            return .empty
        case let .remove(deviceID, path):
            try await transport(for: deviceID).remove(path)
            return .empty
        case let .rename(deviceID, from, dest):
            try await transport(for: deviceID).rename(from, to: dest)
            return .empty
        }
    }
}
```

- [ ] **Step 4: Implement registry helper**

Write `FreeDroid/IPC/XPCConnectionRegistry.swift`:

```swift
import Foundation
import FreeDroidDomain

@MainActor
final class XPCConnectionRegistry {
    private(set) var server: XPCFileServer?

    func start(registry: DeviceRegistry) {
        let handler = XPCFileServerHandler(registry: registry)
        server = XPCFileServer(handler: handler)
        server?.start()
    }
}
```

- [ ] **Step 5: Start the server in `AppContainer`**

In `FreeDroid/AppContainer.swift`:

```swift
    let xpcRegistry = XPCConnectionRegistry()

    func start() async {
        try? await registry.start()
        xpcRegistry.start(registry: registry)
    }
```

- [ ] **Step 6: Add Mach service entitlement to the app**

In Xcode, edit `FreeDroid.entitlements`:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.merkost.freedroid</string>
</array>
<key>com.apple.security.temporary-exception.mach-register.global-name</key>
<array>
    <string>com.merkost.freedroid.XPCFileServer</string>
</array>
```

- [ ] **Step 7: Build and commit**

`⌘B`. Expected: app builds.

```bash
git add FreeDroid
git commit -m "feat(ipc): add app-side XPCFileServer wired to DeviceRegistry"
```

---

## Task 3: Create the `FreeDroidFS` extension target in Xcode

**Files:**
- Create via Xcode: `FreeDroidFS/Info.plist`, `FreeDroidFS/FreeDroidFS.entitlements`

This task requires Xcode UI interaction.

- [ ] **Step 1: Add the target**

In Xcode: File → New → Target → macOS → File System Extension → Next.

Settings:
- Product Name: `FreeDroidFS`
- Team: same as app
- Bundle Identifier: `com.merkost.freedroid.FreeDroidFS`
- Embed in Application: `FreeDroid`

Xcode generates `FreeDroidFS/` folder with placeholder Swift files and `Info.plist`.

- [ ] **Step 2: Configure the extension `Info.plist`**

In `FreeDroidFS/Info.plist`, add:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>FSModuleType</key>
        <string>com.apple.fskit.fsmodule</string>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.fskit.fsmodule</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).FreeDroidFSModule</string>
</dict>
```

- [ ] **Step 3: Configure entitlements**

In `FreeDroidFS/FreeDroidFS.entitlements`:

```xml
<dict>
    <key>com.apple.application-identifier</key>
    <string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>com.apple.developer.fskit.fsmodule</key>
    <true/>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.merkost.freedroid</string>
    </array>
</dict>
```

- [ ] **Step 4: Add `FreeDroidIPC` and `FreeDroidDomain` to the extension target's linked frameworks**

In the FreeDroidFS target → General → Frameworks, Libraries, and Embedded Content → add `FreeDroidIPC` and `FreeDroidDomain`.

- [ ] **Step 5: Commit**

```bash
git add FreeDroidFS FreeDroid.xcodeproj
git commit -m "feat(fskit): scaffold FreeDroidFS extension target"
```

---

## Task 4: Extension-side `XPCClient` and `ErrnoMapping`

**Files:**
- Create: `FreeDroidFS/XPCClient.swift`
- Create: `FreeDroidFS/ErrnoMapping.swift`

- [ ] **Step 1: Implement `XPCClient`**

Write `FreeDroidFS/XPCClient.swift`:

```swift
import Foundation
import FreeDroidIPC

@objc protocol XPCFileServerProtocol {
    func send(_ payload: Data) async -> Data
}

actor XPCClient {
    private var connection: NSXPCConnection?

    func proxy() -> XPCFileServerProtocol {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: IPCEndpoint.machServiceName, options: [])
            c.remoteObjectInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
            c.invalidationHandler = { [weak self] in
                Task { await self?.invalidate() }
            }
            c.resume()
            connection = c
        }
        return connection!.remoteObjectProxy as! XPCFileServerProtocol
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    func send<T>(_ request: IPCRequest, expecting: T.Type) async throws -> T where T: Decodable {
        let proxy = proxy()
        let payload = try IPCCoder.encoder.encode(request)
        let responseData = await proxy.send(payload)
        let response = try IPCCoder.decoder.decode(IPCResponse.self, from: responseData)
        switch response {
        case .entries(let entries) where T.self == [RemoteEntry].self:
            return entries as! T
        case .entry(let entry) where T.self == RemoteEntry.self:
            return entry as! T
        case .data(let data) where T.self == Data.self:
            return data as! T
        case .empty where T.self == Void.self:
            return () as! T
        case .failure(let ipcError):
            switch ipcError {
            case .transport(let t): throw t
            case .noTransport: throw TransportError.notConnected
            case .decodingFailed(let m): throw TransportError.ioFailure(message: m)
            }
        default:
            throw TransportError.ioFailure(message: "Unexpected XPC response")
        }
    }
}

import FreeDroidDomain
```

- [ ] **Step 2: Implement errno mapping**

Write `FreeDroidFS/ErrnoMapping.swift`:

```swift
import Foundation
import FreeDroidDomain

enum ErrnoMapping {
    static func errno(for error: TransportError) -> Int32 {
        switch error {
        case .notConnected: ENODEV
        case .unauthorized: EACCES
        case .timeout: ETIMEDOUT
        case .ioFailure: EIO
        case .notFound: ENOENT
        case .alreadyExists: EEXIST
        case .unsupported: ENOTSUP
        case .cancelled: ECANCELED
        }
    }
}
```

- [ ] **Step 3: Build**

`⌘B`. Expected: extension target builds.

- [ ] **Step 4: Commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): add XPCClient and errno mapping in extension"
```

---

## Task 5: Implement `FreeDroidFSModule`, `FreeDroidVolume`, `FreeDroidItem`

**Files:**
- Create: `FreeDroidFS/FreeDroidFSModule.swift`
- Create: `FreeDroidFS/FreeDroidVolume.swift`
- Create: `FreeDroidFS/FreeDroidItem.swift`

- [ ] **Step 1: Implement `FreeDroidItem`**

Write `FreeDroidFS/FreeDroidItem.swift`:

```swift
import Foundation
import FSKit
import FreeDroidDomain

final class FreeDroidItem: FSItem {
    let entry: RemoteEntry
    let deviceID: DeviceID

    init(deviceID: DeviceID, entry: RemoteEntry) {
        self.deviceID = deviceID
        self.entry = entry
        super.init()
    }
}
```

- [ ] **Step 2: Implement `FreeDroidVolume`**

Write `FreeDroidFS/FreeDroidVolume.swift`:

```swift
import Foundation
import FSKit
import FreeDroidDomain
import FreeDroidIPC

final class FreeDroidVolume: FSVolume, FSVolume.Operations {
    let deviceID: DeviceID
    let client: XPCClient
    let rootEntry: RemoteEntry

    init(deviceID: DeviceID, displayName: String, client: XPCClient) {
        self.deviceID = deviceID
        self.client = client
        self.rootEntry = RemoteEntry(
            path: .root,
            name: displayName,
            kind: .directory,
            sizeBytes: nil,
            modifiedAt: nil,
            isHidden: false
        )
        super.init(volumeID: FSVolume.Identifier(uuid: UUID()), volumeName: displayName)
    }

    func enumerateDirectory(_ item: FSItem) async throws -> [FSItem] {
        guard let dir = item as? FreeDroidItem else { return [] }
        let entries: [RemoteEntry] = try await client.send(.list(deviceID: dir.deviceID, path: dir.entry.path), expecting: [RemoteEntry].self)
        return entries.map { FreeDroidItem(deviceID: dir.deviceID, entry: $0) }
    }

    func lookupItem(named name: String, in parent: FSItem) async throws -> FSItem? {
        guard let parent = parent as? FreeDroidItem else { return nil }
        let path = parent.entry.path.appending(name)
        do {
            let entry: RemoteEntry = try await client.send(.stat(deviceID: parent.deviceID, path: path), expecting: RemoteEntry.self)
            return FreeDroidItem(deviceID: parent.deviceID, entry: entry)
        } catch TransportError.notFound {
            return nil
        }
    }

    func readFile(_ item: FSItem, offset: Int64, length: Int) async throws -> Data {
        guard let file = item as? FreeDroidItem else { return Data() }
        return try await client.send(.read(deviceID: file.deviceID, path: file.entry.path, offset: offset, length: length), expecting: Data.self)
    }

    func writeFile(_ item: FSItem, data: Data, offset: Int64) async throws {
        guard let file = item as? FreeDroidItem else { return }
        _ = try await client.send(.write(deviceID: file.deviceID, path: file.entry.path, data: data, offset: offset), expecting: Data.self)
    }

    func createItem(named name: String, in parent: FSItem, isDirectory: Bool) async throws -> FSItem {
        guard let parent = parent as? FreeDroidItem else { throw TransportError.notConnected }
        let path = parent.entry.path.appending(name)
        if isDirectory {
            _ = try await client.send(.mkdir(deviceID: parent.deviceID, path: path), expecting: Data.self)
        } else {
            _ = try await client.send(.write(deviceID: parent.deviceID, path: path, data: Data(), offset: 0), expecting: Data.self)
        }
        let entry: RemoteEntry = try await client.send(.stat(deviceID: parent.deviceID, path: path), expecting: RemoteEntry.self)
        return FreeDroidItem(deviceID: parent.deviceID, entry: entry)
    }

    func removeItem(_ item: FSItem) async throws {
        guard let item = item as? FreeDroidItem else { return }
        _ = try await client.send(.remove(deviceID: item.deviceID, path: item.entry.path), expecting: Data.self)
    }

    func renameItem(_ item: FSItem, newName: String) async throws -> FSItem {
        guard let item = item as? FreeDroidItem else { throw TransportError.notConnected }
        let parent = item.entry.path.parent ?? .root
        let dest = parent.appending(newName)
        _ = try await client.send(.rename(deviceID: item.deviceID, from: item.entry.path, to: dest), expecting: Data.self)
        let entry: RemoteEntry = try await client.send(.stat(deviceID: item.deviceID, path: dest), expecting: RemoteEntry.self)
        return FreeDroidItem(deviceID: item.deviceID, entry: entry)
    }
}
```

- [ ] **Step 3: Implement `FreeDroidFSModule`**

Write `FreeDroidFS/FreeDroidFSModule.swift`:

```swift
import Foundation
import FSKit
import FreeDroidDomain

final class FreeDroidFSModule: FSUnaryFileSystem, FSUnaryFileSystem.Operations {
    let client = XPCClient()

    func probe(resource: FSResource) async throws -> FSProbeResult {
        .recognized(.init(identifier: UUID(), name: "FreeDroid"))
    }

    func load(resource: FSResource, options: FSTaskOptions) async throws -> FSVolume {
        let deviceID = DeviceID(raw: resource.urlComponents.host ?? "unknown")
        let displayName = resource.urlComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return FreeDroidVolume(deviceID: deviceID, displayName: displayName.isEmpty ? "Android Device" : displayName, client: client)
    }
}
```

- [ ] **Step 4: Build the extension**

`⌘B`. Expected: extension builds; may produce warnings about FSKit being a beta API — acceptable.

- [ ] **Step 5: Commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): implement FSUnaryFileSystem, FSVolume, FSItem"
```

---

## Task 6: Register volumes from the app on device attach

**Files:**
- Modify: `FreeDroid/AppContainer.swift`

- [ ] **Step 1: Register mount per device**

Add to `FreeDroid/AppContainer.swift`:

```swift
import FSKit

    private var mountTask: Task<Void, Never>?

    func observeDevicesForMounting() {
        mountTask = Task {
            for await snapshot in await registry.observe() {
                for device in snapshot {
                    await mount(device)
                }
            }
        }
    }

    private func mount(_ device: Device) async {
        let resourceURL = URL(string: "freedroid://\(device.id.raw)/\(device.displayName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "Android")")!
        let request = FSResourceURL(url: resourceURL)
        do {
            try await FSFileSystemManager.shared.mount(resource: request, atPath: nil, options: [])
        } catch {
            print("Mount failed: \(error)")
        }
    }
```

(The `print` is acceptable inside the helper that surfaces a mount diagnostic; if SwiftLint flags it, replace with `Logger().error`.)

Call `observeDevicesForMounting()` inside `start()` after `xpcRegistry.start`.

- [ ] **Step 2: Build and run with an authorized phone plugged in**

`⌘R`. Expected: after a few seconds, `/Volumes/Pixel 8 Pro` (or your device name) appears in Finder. Open it; directory contents show.

- [ ] **Step 3: Commit**

```bash
git add FreeDroid
git commit -m "feat(fskit): mount devices as FSKit volumes from app"
```

---

## Task 7: Smoke-test reads, writes, deletes

This is a manual integration verification step.

- [ ] **Step 1: Read test**

In Finder, navigate into `/Volumes/<device>/sdcard/DCIM`. Open an image. Quick Look it. Expected: image displays.

- [ ] **Step 2: Write test**

Drag a small file from the Mac into a folder on the mounted volume. Expected: appears on phone.

- [ ] **Step 3: Rename test**

Right-click → Rename. Expected: rename succeeds.

- [ ] **Step 4: Delete test**

Move a test file to trash on the volume. Expected: file disappears (moved to `.FreeDroid/Trash/` on device, per Plan #5 future enhancement; minimum: file is removed).

- [ ] **Step 5: Document any issues**

If anything fails, capture the FSKit signposts:

```bash
log show --predicate 'subsystem == "com.apple.fskit"' --last 5m
```

Open an issue in `docs/known-issues.md` (create if missing) documenting the symptom and reproducer.

---

## Task 8: Update CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add `test-ipc` job**

```yaml
  test-ipc:
    name: Build FreeDroidIPC
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'
      - run: cd Packages/FreeDroidIPC && swift build
```

Update `build-app` to build both targets:

```yaml
      - name: Build app + extension
        run: |
          xcodebuild \
            -workspace FreeDroid.xcworkspace \
            -scheme FreeDroid \
            -destination 'platform=macOS' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            build
```

The `FreeDroidFS` extension builds as part of the app scheme.

- [ ] **Step 2: Commit**

```bash
git add .github
git commit -m "ci: build FreeDroidIPC and FreeDroidFS extension"
```

---

## Done When

- Plugging in an authorized Android phone results in a volume in Finder named after the device within a few seconds.
- Browsing the volume in Finder lists directories and files.
- Reading files from the volume works (Quick Look, drag-to-Mac).
- Writing files into the volume works (drag-from-Mac).
- Renaming and deleting work.
- Ejecting the device unmounts the volume cleanly.
- App + extension build in CI.

## Self-Review

- Spec §4.1 (two-process model) → app + FSKit extension.
- Spec §7 (FSKit lifecycle, callbacks, permissions) → Tasks 4–6.
- Spec §13 (FSKit risk) → `MountStrategy` protocol from Plan #1 means we can pivot to FPX later without rewriting the rest.
- Spec §11.4 (entitlements) → Task 3 (`com.apple.developer.fskit.fsmodule`).
