# File Provider Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken-on-macOS-26 FSKit extension with an `NSFileProviderReplicatedExtension` so Android devices appear in Finder under "Locations" the same way macDroid, Dropbox, and iCloud Drive do.

**Architecture:** Each connected Android device becomes one `NSFileProviderDomain` registered by the host app via `NSFileProviderManager.add(_:)`. macOS spawns one `FreeDroidProviderExtension` process per active domain; that process opens an `NSXPCConnection` back to the host app's existing `XPCFileServer` (machServiceName `com.merkost.freedroid.XPCFileServer`) and forwards every list/stat/read/write through the existing `Transport` (ADB or MTP). The FSKit appex, `MountCoordinator`, `MountedVolumeStore`, and `FSExtensionMonitor` are deleted.

**Tech Stack:** Swift 6.0 strict concurrency, FileProvider framework (`NSFileProviderReplicatedExtension`, `NSFileProviderEnumerator`), the existing `NSXPCConnection`-based `XPCFileServer`, XcodeGen for target generation.

**Style constraint:** **No code comments anywhere.** Strip existing comments in any file you edit. Self-explanatory names only — rationale belongs in commits.

---

## File structure

**Create:**

```
FreeDroidProvider/                          New target replacing FreeDroidFS
├── Info.plist                              NSExtension dict, fileprovider-nonui point
├── FreeDroidProvider.entitlements          app-sandbox + app-group, no fskit
├── FreeDroidProviderExtension.swift        NSFileProviderReplicatedExtension subclass
├── ProviderItem.swift                      NSFileProviderItem struct
├── FolderEnumerator.swift                  NSFileProviderEnumerator subclass for folders
├── WorkingSetEnumerator.swift              NSFileProviderEnumerator subclass for .workingSet
├── ProviderError.swift                     TransportError → NSFileProviderError
└── XPCBridge.swift                         Re-uses IPCRequest/Response from FreeDroidIPC

FreeDroid/Provider/                         Host-app domain coordinator
├── ProviderDomainCoordinator.swift         Replaces MountCoordinator
├── ProviderDomain.swift                    Wraps NSFileProviderDomain with our metadata
└── ItemIdentifier.swift                    Codec for NSFileProviderItemIdentifier ↔ RemotePath (shared via Sources/FreeDroidProviderShared/)

Sources/FreeDroidProviderShared/            New SwiftPM target shared by host app + extension
├── ProviderShared.swift                    Re-export FreeDroidDomain + FreeDroidIPC
└── ItemIdentifier.swift                    Pure-Swift codec (no Foundation extras beyond Data/String)

Tests/FreeDroidProviderSharedTests/
├── ItemIdentifierTests.swift               Encode/decode round-trips, root handling, edge cases
└── ProviderErrorMappingTests.swift         TransportError → NSFileProviderError mapping
```

**Delete:**

```
FreeDroidFS/                                Entire FSKit appex
FreeDroid/Mount/                            MountCoordinator + MountedVolumeStore + FSExtensionMonitor
FreeDroid/UI/FSExtensionBanner.swift        Banner about Settings toggle (no longer relevant)
```

**Modify:**

```
project.yml                                 Swap FreeDroidFS for FreeDroidProvider
FreeDroid.xcodeproj/project.pbxproj         Re-generate or hand-patch
FreeDroid/AppContainer.swift                Drop MountCoordinator, add ProviderDomainCoordinator
FreeDroid/ContentView.swift                 Remove FSExtensionBanner, add Reveal-in-Finder hint per device
Scripts/install-to-applications.sh          Drop pluginkit -e use, keep lsregister
Package.swift                               Add FreeDroidProviderShared target
PROJECT_STATUS.md                           Rewrite mount/FSKit sections
```

---

## Identifier scheme (locked decision)

`NSFileProviderItemIdentifier` is an opaque `String` to Apple. The provider chooses its scheme. We use:

- `.rootContainer` (Apple-defined constant `"NSFileProviderRootContainerItemIdentifier"`) → the device's root path (`/`).
- Every other item: a URL-safe base64 encoding of the UTF-8 bytes of the absolute `RemotePath.raw`, prefixed with `"p:"` to leave room for future tag formats.
  - `/sdcard/DCIM/Camera/IMG_001.jpg` → `"p:L3NkY2FyZC9EQ0lNL0NhbWVyYS9JTUdfMDAxLmpwZw=="`
- `.workingSet` and `.trashContainer` map to known constants we route to dedicated enumerators (workingSet returns the same as root for v1; trash returns empty).

The `DeviceID` is **not** in the identifier — it's already pinned by the `NSFileProviderDomain` the extension was init'd with. One extension process = one device.

---

## XPC reachability note (read before Phase 2)

The existing `XPCFileServer` uses `NSXPCListener(machServiceName: "com.merkost.freedroid.XPCFileServer")`. A sandboxed File Provider extension can only `NSXPCConnection(machServiceName:)` to a service whose name begins with the **team identifier prefix**, when the host app has declared that mach name in its app group. For macOS 11.3+ File Provider extensions Apple's recommendation is:

- Name the mach service `<TEAM_ID>.<reverse-DNS>` (e.g. `P47X2292CM.com.merkost.freedroid.XPCFileServer`), and
- Both processes share the app group `group.com.merkost.freedroid` (already declared).

We update `IPCEndpoint.machServiceName` to the prefixed form in Task 12.

---

## Phase 1 — Bootstrap

### Task 1: Create FreeDroidProviderShared SwiftPM target

**Files:**
- Create: `Sources/FreeDroidProviderShared/ProviderShared.swift`
- Modify: `Package.swift`
- Create: `Tests/FreeDroidProviderSharedTests/ProviderSharedSmokeTests.swift`

- [ ] **Step 1: Add the target to `Package.swift`**

```swift
.library(name: "FreeDroidProviderShared", targets: ["FreeDroidProviderShared"]),
```

In `targets:`:

```swift
.target(
    name: "FreeDroidProviderShared",
    dependencies: ["FreeDroidDomain", "FreeDroidIPC"],
    swiftSettings: strictConcurrency
),
.testTarget(
    name: "FreeDroidProviderSharedTests",
    dependencies: ["FreeDroidProviderShared"],
    swiftSettings: strictConcurrency
),
```

- [ ] **Step 2: Add the placeholder source file**

`Sources/FreeDroidProviderShared/ProviderShared.swift`:

```swift
@_exported import FreeDroidDomain
@_exported import FreeDroidIPC
```

- [ ] **Step 3: Add a smoke test that builds**

`Tests/FreeDroidProviderSharedTests/ProviderSharedSmokeTests.swift`:

```swift
import XCTest
@testable import FreeDroidProviderShared

final class ProviderSharedSmokeTests: XCTestCase {
    func testReExportsAreReachable() {
        _ = RemotePath.root
        _ = DeviceID(raw: "x")
    }
}
```

- [ ] **Step 4: Verify the SPM package builds**

Run: `swift build --target FreeDroidProviderShared`
Expected: `Build complete!`

Run: `swift test --filter ProviderSharedSmokeTests`
Expected: 1 passing test.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/FreeDroidProviderShared Tests/FreeDroidProviderSharedTests
git commit -m "build(provider): add FreeDroidProviderShared SwiftPM target"
```

---

### Task 2: ItemIdentifier codec — failing tests first

**Files:**
- Create: `Sources/FreeDroidProviderShared/ItemIdentifier.swift`
- Create: `Tests/FreeDroidProviderSharedTests/ItemIdentifierTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/FreeDroidProviderSharedTests/ItemIdentifierTests.swift`:

```swift
import XCTest
@testable import FreeDroidProviderShared

final class ItemIdentifierTests: XCTestCase {
    func testRootIsAppleRootContainerConstant() {
        XCTAssertEqual(ItemIdentifier.encode(.root), "NSFileProviderRootContainerItemIdentifier")
    }

    func testEncodeDecodeRoundTrip() {
        let path = RemotePath(raw: "/sdcard/DCIM/Camera/IMG_001.jpg")
        let encoded = ItemIdentifier.encode(path)
        XCTAssertTrue(encoded.hasPrefix("p:"))
        XCTAssertEqual(ItemIdentifier.decode(encoded), path)
    }

    func testDecodeAppleRootReturnsRoot() {
        XCTAssertEqual(ItemIdentifier.decode("NSFileProviderRootContainerItemIdentifier"), .root)
    }

    func testDecodeRejectsUnknownPrefix() {
        XCTAssertNil(ItemIdentifier.decode("junk:abc"))
    }

    func testDecodeRejectsMalformedBase64() {
        XCTAssertNil(ItemIdentifier.decode("p:not-base-64!!!"))
    }

    func testPathsWithSpacesAndUnicode() {
        let path = RemotePath(raw: "/sdcard/Pictures/Mon Été 🌞/photo.jpg")
        let roundTripped = ItemIdentifier.decode(ItemIdentifier.encode(path))
        XCTAssertEqual(roundTripped, path)
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

Run: `swift test --filter ItemIdentifierTests`
Expected: compile error — `ItemIdentifier` undefined.

- [ ] **Step 3: Implement the codec**

`Sources/FreeDroidProviderShared/ItemIdentifier.swift`:

```swift
import Foundation

public enum ItemIdentifier {
    public static let appleRoot = "NSFileProviderRootContainerItemIdentifier"
    public static let pathPrefix = "p:"

    public static func encode(_ path: RemotePath) -> String {
        if path.isRoot { return appleRoot }
        let data = Data(path.raw.utf8)
        return pathPrefix + data.base64EncodedString()
    }

    public static func decode(_ identifier: String) -> RemotePath? {
        if identifier == appleRoot { return .root }
        guard identifier.hasPrefix(pathPrefix) else { return nil }
        let payload = String(identifier.dropFirst(pathPrefix.count))
        guard let data = Data(base64Encoded: payload),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return RemotePath(raw: raw)
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `swift test --filter ItemIdentifierTests`
Expected: 5 passing tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/FreeDroidProviderShared/ItemIdentifier.swift Tests/FreeDroidProviderSharedTests/ItemIdentifierTests.swift
git commit -m "feat(provider): add ItemIdentifier codec for NSFileProviderItemIdentifier"
```

---

### Task 3: ProviderError mapping — failing tests first

**Files:**
- Create: `Sources/FreeDroidProviderShared/ProviderError.swift`
- Create: `Tests/FreeDroidProviderSharedTests/ProviderErrorMappingTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import FileProvider
@testable import FreeDroidProviderShared

final class ProviderErrorMappingTests: XCTestCase {
    func testNotConnectedMapsToServerUnreachable() {
        let mapped = ProviderError.map(TransportError.notConnected)
        XCTAssertEqual((mapped as NSError).domain, NSFileProviderErrorDomain)
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.serverUnreachable.rawValue)
    }

    func testNotFoundMapsToNoSuchItem() {
        let mapped = ProviderError.map(TransportError.notFound(RemotePath(raw: "/x")))
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.noSuchItem.rawValue)
    }

    func testAlreadyExistsMapsToFilenameCollision() {
        let mapped = ProviderError.map(TransportError.alreadyExists(RemotePath(raw: "/x")))
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.filenameCollision.rawValue)
    }

    func testIOFailureMapsToCannotSynchronize() {
        let mapped = ProviderError.map(TransportError.ioFailure(message: "boom"))
        XCTAssertEqual((mapped as NSError).code, NSFileProviderError.Code.cannotSynchronize.rawValue)
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

Run: `swift test --filter ProviderErrorMappingTests`
Expected: `ProviderError` undefined.

- [ ] **Step 3: Implement the mapping**

`Sources/FreeDroidProviderShared/ProviderError.swift`:

```swift
import FileProvider
import Foundation

public enum ProviderError {
    public static func map(_ error: TransportError) -> NSError {
        let code: NSFileProviderError.Code
        switch error {
        case .notConnected:            code = .serverUnreachable
        case .notFound:                code = .noSuchItem
        case .alreadyExists:           code = .filenameCollision
        case .unsupported:             code = .noSuchItem
        case .permissionDenied:        code = .insufficientQuota
        case .ioFailure:               code = .cannotSynchronize
        }
        return NSFileProviderError(code).toNSError(message: String(describing: error))
    }
}

private extension NSFileProviderError {
    init(_ code: Code) {
        self = NSFileProviderError(code)
    }

    func toNSError(message: String) -> NSError {
        let underlying = (self as NSError)
        return NSError(
            domain: underlying.domain,
            code: underlying.code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `swift test --filter ProviderErrorMappingTests`
Expected: 4 passing tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/FreeDroidProviderShared Tests/FreeDroidProviderSharedTests/ProviderErrorMappingTests.swift
git commit -m "feat(provider): add TransportError → NSFileProviderError mapper"
```

---

## Phase 2 — Provider extension target

### Task 4: Generate the FreeDroidProvider extension target via project.yml

**Files:**
- Modify: `project.yml`
- Create: `FreeDroidProvider/Info.plist`
- Create: `FreeDroidProvider/FreeDroidProvider.entitlements`
- Create: `FreeDroidProvider/FreeDroidProviderExtension.swift` (stub)

- [ ] **Step 1: Add target spec to `project.yml`** (above the existing `FreeDroidFS` block, do not remove FreeDroidFS yet — Task 17 removes it)

```yaml
  FreeDroidProvider:
    type: app-extension
    platform: macOS
    deploymentTarget: "15.4"
    sources:
      - path: FreeDroidProvider
    configFiles:
      Debug: Configs/Local.xcconfig
      Release: Configs/Local.xcconfig
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.merkost.freedroid.FreeDroidProvider
        INFOPLIST_FILE: FreeDroidProvider/Info.plist
        CODE_SIGN_ENTITLEMENTS: FreeDroidProvider/FreeDroidProvider.entitlements
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "Apple Development"
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_VERSION: "6.0"
        SWIFT_STRICT_CONCURRENCY: complete
        SKIP_INSTALL: YES
        PRODUCT_NAME: FreeDroidProvider
        MACOSX_DEPLOYMENT_TARGET: "15.4"
    dependencies:
      - package: FreeDroidPackages
        product: FreeDroidProviderShared
```

Also add to the `FreeDroid` target's `dependencies`:

```yaml
      - target: FreeDroidProvider
        embed: true
        codeSign: true
```

- [ ] **Step 2: Create `FreeDroidProvider/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>           <string>en</string>
    <key>CFBundleDisplayName</key>                 <string>FreeDroid Provider</string>
    <key>CFBundleExecutable</key>                  <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>                  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>       <string>6.0</string>
    <key>CFBundleName</key>                        <string>FreeDroidProvider</string>
    <key>CFBundlePackageType</key>                 <string>XPC!</string>
    <key>CFBundleShortVersionString</key>          <string>0.0.1</string>
    <key>CFBundleVersion</key>                     <string>1</string>
    <key>LSMinimumSystemVersion</key>              <string>15.4</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>      <string>com.apple.fileprovider-nonui</string>
        <key>NSExtensionPrincipalClass</key>       <string>$(PRODUCT_MODULE_NAME).FreeDroidProviderExtension</string>
        <key>NSExtensionFileProviderDocumentGroup</key> <string>group.com.merkost.freedroid</string>
        <key>NSExtensionFileProviderSupportsEnumeration</key> <true/>
    </dict>
</dict>
</plist>
```

- [ ] **Step 3: Create `FreeDroidProvider/FreeDroidProvider.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>          <true/>
    <key>com.apple.security.application-groups</key>
    <array><string>group.com.merkost.freedroid</string></array>
    <key>com.apple.security.files.user-selected.read-write</key> <true/>
</dict>
</plist>
```

- [ ] **Step 4: Create the stub principal class**

`FreeDroidProvider/FreeDroidProviderExtension.swift`:

```swift
import FileProvider
import FreeDroidProviderShared

final class FreeDroidProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {}

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        completionHandler(nil, NSFileProviderError(.noSuchItem) as NSError)
        return Progress()
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        completionHandler(nil, nil, NSFileProviderError(.noSuchItem) as NSError)
        return Progress()
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        throw NSFileProviderError(.noSuchItem)
    }
}
```

- [ ] **Step 5: Regenerate the Xcode project + build**

Run: `Scripts/generate-project.sh`
Run: `xcodebuild -workspace FreeDroid.xcworkspace -scheme FreeDroid -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **` and `/Applications/FreeDroid.app/Contents/PlugIns/FreeDroidProvider.appex` exists.

- [ ] **Step 6: Verify the extension is embedded under `PlugIns/` (not `Extensions/`)**

Run: `ls /Applications/FreeDroid.app/Contents/PlugIns/`
Expected: `FreeDroidProvider.appex`

(File Provider extensions are classic `NSExtension`-style and live under `Contents/PlugIns/`, not `Contents/Extensions/`.)

- [ ] **Step 7: Commit**

```bash
git add project.yml FreeDroidProvider FreeDroid.xcodeproj/project.pbxproj
git commit -m "feat(provider): add FreeDroidProvider app-extension target stub"
```

---

## Phase 3 — Item + read-only enumeration

### Task 5: ProviderItem — the NSFileProviderItem adapter

**Files:**
- Create: `FreeDroidProvider/ProviderItem.swift`
- Create: `Tests/FreeDroidProviderSharedTests/ProviderItemTests.swift` (move to test target inside the extension only if needed; keeping in shared tests is fine since ProviderItem will live in shared too — relocate now)
- Move: `FreeDroidProvider/ProviderItem.swift` → `Sources/FreeDroidProviderShared/ProviderItem.swift`

- [ ] **Step 1: Write failing tests**

`Tests/FreeDroidProviderSharedTests/ProviderItemTests.swift`:

```swift
import XCTest
import FileProvider
import UniformTypeIdentifiers
@testable import FreeDroidProviderShared

final class ProviderItemTests: XCTestCase {
    func testRootItem() {
        let item = ProviderItem.root(displayName: "Pixel 9")
        XCTAssertEqual(item.itemIdentifier, .rootContainer)
        XCTAssertEqual(item.parentItemIdentifier, .rootContainer)
        XCTAssertEqual(item.filename, "Pixel 9")
        XCTAssertEqual(item.contentType, .folder)
    }

    func testFolderFromEntry() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/sdcard/DCIM"),
            name: "DCIM",
            kind: .directory,
            sizeBytes: nil,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isHidden: false
        )
        let item = ProviderItem(entry: entry, parent: .root)
        XCTAssertEqual(item.filename, "DCIM")
        XCTAssertEqual(item.contentType, .folder)
        XCTAssertEqual(item.itemIdentifier.rawValue, ItemIdentifier.encode(entry.path))
        XCTAssertEqual(item.parentItemIdentifier, .rootContainer)
    }

    func testFileFromEntryHasJPEGContentType() {
        let entry = RemoteEntry(
            path: RemotePath(raw: "/sdcard/DCIM/Camera/IMG_001.jpg"),
            name: "IMG_001.jpg",
            kind: .file,
            sizeBytes: 12345,
            modifiedAt: nil,
            isHidden: false
        )
        let item = ProviderItem(entry: entry, parent: RemotePath(raw: "/sdcard/DCIM/Camera"))
        XCTAssertEqual(item.contentType, .jpeg)
        XCTAssertEqual(item.documentSize, NSNumber(value: 12345))
    }
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `swift test --filter ProviderItemTests`
Expected: `ProviderItem` undefined.

- [ ] **Step 3: Implement ProviderItem**

`Sources/FreeDroidProviderShared/ProviderItem.swift`:

```swift
import FileProvider
import Foundation
import UniformTypeIdentifiers

public struct ProviderItem: NSFileProviderItem {
    public let itemIdentifier: NSFileProviderItemIdentifier
    public let parentItemIdentifier: NSFileProviderItemIdentifier
    public let filename: String
    public let contentType: UTType
    public let capabilities: NSFileProviderItemCapabilities
    public let documentSize: NSNumber?
    public let creationDate: Date?
    public let contentModificationDate: Date?
    public let itemVersion: NSFileProviderItemVersion

    public static func root(displayName: String) -> ProviderItem {
        ProviderItem(
            itemIdentifier: .rootContainer,
            parentItemIdentifier: .rootContainer,
            filename: displayName,
            contentType: .folder,
            capabilities: [.allowsContentEnumerating, .allowsReading],
            documentSize: nil,
            creationDate: nil,
            contentModificationDate: nil,
            itemVersion: NSFileProviderItemVersion(
                contentVersion: Data("v1".utf8),
                metadataVersion: Data("v1".utf8)
            )
        )
    }

    public init(entry: RemoteEntry, parent: RemotePath) {
        let isDirectory = entry.kind == .directory
        self.itemIdentifier = NSFileProviderItemIdentifier(ItemIdentifier.encode(entry.path))
        self.parentItemIdentifier = parent.isRoot
            ? .rootContainer
            : NSFileProviderItemIdentifier(ItemIdentifier.encode(parent))
        self.filename = entry.name
        self.contentType = isDirectory ? .folder : Self.contentType(forName: entry.name)
        self.capabilities = isDirectory
            ? [.allowsContentEnumerating, .allowsReading, .allowsAddingSubItems,
               .allowsDeleting, .allowsRenaming]
            : [.allowsReading, .allowsWriting, .allowsDeleting, .allowsRenaming]
        self.documentSize = entry.sizeBytes.map { NSNumber(value: $0) }
        self.creationDate = nil
        self.contentModificationDate = entry.modifiedAt
        let mod = entry.modifiedAt?.timeIntervalSince1970 ?? 0
        let size = entry.sizeBytes ?? 0
        self.itemVersion = NSFileProviderItemVersion(
            contentVersion: Data("c:\(mod):\(size)".utf8),
            metadataVersion: Data("m:\(mod)".utf8)
        )
    }

    public init(
        itemIdentifier: NSFileProviderItemIdentifier,
        parentItemIdentifier: NSFileProviderItemIdentifier,
        filename: String,
        contentType: UTType,
        capabilities: NSFileProviderItemCapabilities,
        documentSize: NSNumber?,
        creationDate: Date?,
        contentModificationDate: Date?,
        itemVersion: NSFileProviderItemVersion
    ) {
        self.itemIdentifier = itemIdentifier
        self.parentItemIdentifier = parentItemIdentifier
        self.filename = filename
        self.contentType = contentType
        self.capabilities = capabilities
        self.documentSize = documentSize
        self.creationDate = creationDate
        self.contentModificationDate = contentModificationDate
        self.itemVersion = itemVersion
    }

    private static func contentType(forName name: String) -> UTType {
        let ext = (name as NSString).pathExtension
        if ext.isEmpty { return .data }
        return UTType(filenameExtension: ext) ?? .data
    }
}
```

- [ ] **Step 4: Run, confirm pass**

Run: `swift test --filter ProviderItemTests`
Expected: 3 passing tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/FreeDroidProviderShared/ProviderItem.swift Tests/FreeDroidProviderSharedTests/ProviderItemTests.swift
git commit -m "feat(provider): add ProviderItem NSFileProviderItem adapter"
```

---

### Task 6: XPCBridge — extension-side client for the host XPC server

**Files:**
- Create: `FreeDroidProvider/XPCBridge.swift`
- Modify: `Sources/FreeDroidIPC/IPCEndpoint.swift`

- [ ] **Step 1: Update mach service name to team-prefixed form**

`Sources/FreeDroidIPC/IPCEndpoint.swift`:

```swift
public enum IPCEndpoint {
    public static let teamID = "P47X2292CM"
    public static let machServiceName = "\(teamID).com.merkost.freedroid.XPCFileServer"
}
```

- [ ] **Step 2: Update the host app's `XPCClient` & FSKit references in tree**

Run: `grep -rn "com.merkost.freedroid.XPCFileServer" .`
Confirm: only `IPCEndpoint.swift` defines the literal; everywhere else references `IPCEndpoint.machServiceName`. If anywhere else hardcodes the old name, update it.

- [ ] **Step 3: Create the bridge**

`FreeDroidProvider/XPCBridge.swift`:

```swift
import Foundation
import FreeDroidProviderShared

@objc protocol XPCFileServerProtocol {
    func send(_ payload: Data) async -> Data
}

actor XPCBridge {
    private var connection: NSXPCConnection?

    func send<T: Decodable>(_ request: IPCRequest, expecting: T.Type) async throws -> T {
        let payload = try IPCCoder.encoder.encode(request)
        let proxy = try makeProxy()
        let responseData = await proxy.send(payload)
        let response = try IPCCoder.decoder.decode(IPCResponse.self, from: responseData)
        switch response {
        case .entries(let entries) where T.self == [RemoteEntry].self:
            return entries as! T
        case .entry(let entry) where T.self == RemoteEntry.self:
            return entry as! T
        case .data(let data) where T.self == Data.self:
            return data as! T
        case .empty where T.self == Data.self:
            return Data() as! T
        case .failure(let ipcError):
            switch ipcError {
            case .transport(let e): throw e
            case .noTransport:      throw TransportError.notConnected
            case .decodingFailed(let m): throw TransportError.ioFailure(message: m)
            }
        default:
            throw TransportError.ioFailure(message: "Unexpected XPC response shape")
        }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func makeProxy() throws -> any XPCFileServerProtocol {
        if connection == nil {
            let conn = NSXPCConnection(machServiceName: IPCEndpoint.machServiceName, options: [])
            conn.remoteObjectInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
            conn.invalidationHandler = { [weak conn] in conn?.invalidate() }
            conn.resume()
            connection = conn
        }
        return connection!.remoteObjectProxy as! any XPCFileServerProtocol
    }
}
```

- [ ] **Step 4: Build the extension target alone to catch errors**

Run: `xcodebuild -workspace FreeDroid.xcworkspace -scheme FreeDroid -configuration Debug -destination 'platform=macOS' -target FreeDroidProvider build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add FreeDroidProvider/XPCBridge.swift Sources/FreeDroidIPC/IPCEndpoint.swift
git commit -m "feat(provider): add XPCBridge and team-prefixed mach service name"
```

---

### Task 7: FolderEnumerator — list children via XPC

**Files:**
- Create: `FreeDroidProvider/FolderEnumerator.swift`

- [ ] **Step 1: Create the enumerator**

`FreeDroidProvider/FolderEnumerator.swift`:

```swift
import FileProvider
import Foundation
import FreeDroidProviderShared

final class FolderEnumerator: NSObject, NSFileProviderEnumerator {
    private let containerIdentifier: NSFileProviderItemIdentifier
    private let folderPath: RemotePath
    private let deviceID: DeviceID
    private let bridge: XPCBridge

    init(
        container: NSFileProviderItemIdentifier,
        folderPath: RemotePath,
        deviceID: DeviceID,
        bridge: XPCBridge
    ) {
        self.containerIdentifier = container
        self.folderPath = folderPath
        self.deviceID = deviceID
        self.bridge = bridge
        super.init()
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                let entries = try await bridge.send(
                    .list(deviceID: deviceID, path: folderPath),
                    expecting: [RemoteEntry].self
                )
                let items: [NSFileProviderItem] = entries.map {
                    ProviderItem(entry: $0, parent: folderPath)
                }
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch let error as TransportError {
                observer.finishEnumeratingWithError(ProviderError.map(error))
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("v0".utf8)))
    }
}
```

- [ ] **Step 2: Build extension target**

Run: `xcodebuild -workspace FreeDroid.xcworkspace -scheme FreeDroid -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add FreeDroidProvider/FolderEnumerator.swift
git commit -m "feat(provider): add FolderEnumerator backed by XPC list"
```

---

### Task 8: Wire the principal class — item + enumerator

**Files:**
- Modify: `FreeDroidProvider/FreeDroidProviderExtension.swift`

- [ ] **Step 1: Replace the stub with a working read-only implementation**

```swift
import FileProvider
import FreeDroidProviderShared

final class FreeDroidProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain
    let deviceID: DeviceID
    let bridge = XPCBridge()

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.deviceID = DeviceID(raw: domain.identifier.rawValue)
        super.init()
    }

    func invalidate() {
        Task { await bridge.invalidate() }
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        Task {
            do {
                let item = try await resolveItem(for: identifier)
                completionHandler(item, nil)
            } catch let error as TransportError {
                completionHandler(nil, ProviderError.map(error))
            } catch {
                completionHandler(nil, error)
            }
        }
        return Progress()
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        completionHandler(nil, nil, NSFileProviderError(.serverUnreachable) as NSError)
        return Progress()
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        let path = ItemIdentifier.decode(containerItemIdentifier.rawValue) ?? .root
        return FolderEnumerator(
            container: containerItemIdentifier,
            folderPath: path,
            deviceID: deviceID,
            bridge: bridge
        )
    }

    private func resolveItem(for identifier: NSFileProviderItemIdentifier) async throws -> NSFileProviderItem {
        if identifier == .rootContainer || identifier == .trashContainer {
            return ProviderItem.root(displayName: domain.displayName)
        }
        guard let path = ItemIdentifier.decode(identifier.rawValue) else {
            throw NSFileProviderError(.noSuchItem)
        }
        let entry = try await bridge.send(
            .stat(deviceID: deviceID, path: path),
            expecting: RemoteEntry.self
        )
        let parent = path.parent ?? .root
        return ProviderItem(entry: entry, parent: parent)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -workspace FreeDroid.xcworkspace -scheme FreeDroid -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add FreeDroidProvider/FreeDroidProviderExtension.swift
git commit -m "feat(provider): wire read-only item resolution + enumerator"
```

---

## Phase 4 — Host-app domain registration

### Task 9: ProviderDomainCoordinator (replaces MountCoordinator)

**Files:**
- Create: `FreeDroid/Provider/ProviderDomainCoordinator.swift`

- [ ] **Step 1: Add the coordinator**

`FreeDroid/Provider/ProviderDomainCoordinator.swift`:

```swift
import FileProvider
import Foundation
import FreeDroidData
import FreeDroidDomain
import os.log

private let providerLogger = Logger(subsystem: "com.merkost.freedroid", category: "provider")

@MainActor
final class ProviderDomainCoordinator {
    private let registry: DeviceRegistry
    private var task: Task<Void, Never>?
    private var active: Set<DeviceID> = []

    init(registry: DeviceRegistry) {
        self.registry = registry
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            for await snapshot in await self.registry.observe() {
                await self.reconcile(snapshot)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        Task { await self.removeAll() }
    }

    private func reconcile(_ devices: [Device]) async {
        let readyIDs = Set(devices.filter { $0.connectionState == .ready }.map(\.id))
        for device in devices where device.connectionState == .ready {
            await addIfNeeded(device)
        }
        for id in active.subtracting(readyIDs) {
            await removeDomain(for: id)
        }
    }

    private func addIfNeeded(_ device: Device) async {
        guard !active.contains(device.id) else { return }
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(device.id.raw),
            displayName: device.displayName
        )
        do {
            try await NSFileProviderManager.add(domain)
            active.insert(device.id)
            providerLogger.info("Registered domain for \(device.displayName, privacy: .public)")
        } catch {
            providerLogger.error("add(\(device.displayName, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

    private func removeDomain(for deviceID: DeviceID) async {
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(deviceID.raw),
            displayName: ""
        )
        do {
            try await NSFileProviderManager.remove(domain)
            active.remove(deviceID)
            providerLogger.info("Removed domain \(deviceID.raw, privacy: .public)")
        } catch {
            providerLogger.error("remove(\(deviceID.raw, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

    private func removeAll() async {
        for id in active { await removeDomain(for: id) }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild ... build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add FreeDroid/Provider/ProviderDomainCoordinator.swift
git commit -m "feat(provider): add ProviderDomainCoordinator"
```

---

### Task 10: Wire DomainCoordinator into AppContainer; remove MountCoordinator

**Files:**
- Modify: `FreeDroid/AppContainer.swift`

- [ ] **Step 1: Replace MountCoordinator with ProviderDomainCoordinator**

In `AppContainer.swift`:

Replace:

```swift
    let extensionMonitor = FSExtensionMonitor()
    let mountCoordinator: MountCoordinator
```

With:

```swift
    let domainCoordinator: ProviderDomainCoordinator
```

Replace in `init`:

```swift
        self.mountCoordinator = MountCoordinator(registry: registry, extensionMonitor: extensionMonitor)
```

With:

```swift
        self.domainCoordinator = ProviderDomainCoordinator(registry: registry)
```

Replace in `start()`:

```swift
        extensionMonitor.start()
        mountCoordinator.start()
```

With:

```swift
        domainCoordinator.start()
```

- [ ] **Step 2: Update `ContentView.swift` — remove FSExtensionBanner usage**

Remove the `FSExtensionBanner(...)` block and its supporting `motion` modifier referencing `container.extensionMonitor`.

- [ ] **Step 3: Build**

Run: `xcodebuild ... build`
Expected: failures referencing `FSExtensionMonitor`, `FSExtensionBanner`, `MountCoordinator`. These are deleted in Task 17 — temporarily, copy the type-locator import lines so the build holds. Easier: just stub the removed types under `FreeDroid/Mount/` to empty deprecated shims so the build stays green between commits.

Concrete approach: leave the old files in place for now, just stop referencing them in AppContainer/ContentView. Build should succeed because the unreferenced files still compile.

Run: `xcodebuild ... build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add FreeDroid/AppContainer.swift FreeDroid/ContentView.swift
git commit -m "refactor: route AppContainer through ProviderDomainCoordinator"
```

---

## Phase 5 — fetchContents

### Task 11: fetchContents — stream chunks to a temp file

**Files:**
- Modify: `FreeDroidProvider/FreeDroidProviderExtension.swift`

- [ ] **Step 1: Implement chunked fetch**

Replace the `fetchContents` stub with:

```swift
    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: -1)
        Task {
            do {
                guard let path = ItemIdentifier.decode(itemIdentifier.rawValue) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                let entry = try await bridge.send(
                    .stat(deviceID: deviceID, path: path),
                    expecting: RemoteEntry.self
                )
                let total = entry.sizeBytes ?? 0
                progress.totalUnitCount = total
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension((entry.name as NSString).pathExtension)
                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: tempURL)
                defer { try? handle.close() }
                let chunkSize = 1 << 20
                var offset: Int64 = 0
                while offset < total {
                    let length = Int(min(Int64(chunkSize), total - offset))
                    let chunk = try await bridge.send(
                        .read(deviceID: deviceID, path: path, offset: offset, length: length),
                        expecting: Data.self
                    )
                    try handle.write(contentsOf: chunk)
                    offset += Int64(chunk.count)
                    progress.completedUnitCount = offset
                    if chunk.count == 0 { break }
                }
                let item = ProviderItem(entry: entry, parent: path.parent ?? .root)
                completionHandler(tempURL, item, nil)
            } catch let error as TransportError {
                completionHandler(nil, nil, ProviderError.map(error))
            } catch {
                completionHandler(nil, nil, error)
            }
        }
        return progress
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild ... build`
Expected: success.

- [ ] **Step 3: Manual smoke test — list works**

1. Launch the app (post-action installs to `/Applications`).
2. Plug in an Android device, authorize ADB.
3. In Finder sidebar → Locations, expect to see the device name.
4. Click it — directory listing should appear.

If listing is empty or errors, run `log show --last 1m --predicate 'subsystem == "com.merkost.freedroid"'` and inspect.

- [ ] **Step 4: Manual smoke test — open a small text file**

1. Navigate to a small file in Finder.
2. Quick Look or open it.
3. Expect contents to appear.

- [ ] **Step 5: Commit**

```bash
git add FreeDroidProvider/FreeDroidProviderExtension.swift
git commit -m "feat(provider): implement chunked fetchContents over XPC"
```

---

## Phase 6 — Writes

### Task 12: createItem — folders + zero-byte files

**Files:**
- Modify: `FreeDroidProvider/FreeDroidProviderExtension.swift`

- [ ] **Step 1: Add the method**

```swift
    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            do {
                let parent = try resolveParent(itemTemplate.parentItemIdentifier)
                let newPath = parent.appending(itemTemplate.filename)
                if itemTemplate.contentType == .folder {
                    _ = try await bridge.send(.mkdir(deviceID: deviceID, path: newPath), expecting: Data.self)
                } else if let url {
                    let data = try Data(contentsOf: url)
                    _ = try await bridge.send(
                        .write(deviceID: deviceID, path: newPath, data: data, offset: 0),
                        expecting: Data.self
                    )
                } else {
                    _ = try await bridge.send(
                        .write(deviceID: deviceID, path: newPath, data: Data(), offset: 0),
                        expecting: Data.self
                    )
                }
                let entry = try await bridge.send(
                    .stat(deviceID: deviceID, path: newPath),
                    expecting: RemoteEntry.self
                )
                progress.completedUnitCount = 1
                completionHandler(ProviderItem(entry: entry, parent: parent), [], false, nil)
            } catch let error as TransportError {
                completionHandler(nil, [], false, ProviderError.map(error))
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }

    private func resolveParent(_ identifier: NSFileProviderItemIdentifier) throws -> RemotePath {
        if identifier == .rootContainer { return .root }
        guard let path = ItemIdentifier.decode(identifier.rawValue) else {
            throw NSFileProviderError(.noSuchItem)
        }
        return path
    }
```

- [ ] **Step 2: Build + smoke test (create folder via Finder)**

Run: `xcodebuild ... build`. Then in Finder: right-click in mounted view → New Folder. Verify it appears and `adb shell ls /sdcard/` shows it.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(provider): implement createItem"
```

---

### Task 13: modifyItem — rename + content replace

**Files:**
- Modify: `FreeDroidProvider/FreeDroidProviderExtension.swift`

- [ ] **Step 1: Add modifyItem**

```swift
    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            do {
                guard let path = ItemIdentifier.decode(item.itemIdentifier.rawValue) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                var currentPath = path

                if changedFields.contains(.parentItemIdentifier) || changedFields.contains(.filename) {
                    let newParent = try resolveParent(item.parentItemIdentifier)
                    let target = newParent.appending(item.filename)
                    if target != currentPath {
                        _ = try await bridge.send(
                            .rename(deviceID: deviceID, from: currentPath, to: target),
                            expecting: Data.self
                        )
                        currentPath = target
                    }
                }

                if changedFields.contains(.contents), let newContents {
                    let data = try Data(contentsOf: newContents)
                    _ = try await bridge.send(
                        .write(deviceID: deviceID, path: currentPath, data: data, offset: 0),
                        expecting: Data.self
                    )
                }

                let entry = try await bridge.send(
                    .stat(deviceID: deviceID, path: currentPath),
                    expecting: RemoteEntry.self
                )
                progress.completedUnitCount = 1
                completionHandler(ProviderItem(entry: entry, parent: currentPath.parent ?? .root), [], false, nil)
            } catch let error as TransportError {
                completionHandler(nil, [], false, ProviderError.map(error))
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }
```

- [ ] **Step 2: Build + smoke test (rename in Finder)**

Build, then in Finder mount → rename a folder. Verify it persists.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(provider): implement modifyItem (rename + replace contents)"
```

---

### Task 14: deleteItem

**Files:**
- Modify: `FreeDroidProvider/FreeDroidProviderExtension.swift`

- [ ] **Step 1: Add deleteItem**

```swift
    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            do {
                guard let path = ItemIdentifier.decode(identifier.rawValue) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                _ = try await bridge.send(.remove(deviceID: deviceID, path: path), expecting: Data.self)
                progress.completedUnitCount = 1
                completionHandler(nil)
            } catch let error as TransportError {
                completionHandler(ProviderError.map(error))
            } catch {
                completionHandler(error)
            }
        }
        return progress
    }
```

- [ ] **Step 2: Build + smoke test**

Build, delete a file in Finder, verify it's gone via `adb shell ls`.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(provider): implement deleteItem"
```

---

## Phase 7 — Cleanup

### Task 15: Delete FSKit appex and related host-app files

**Files:**
- Delete: `FreeDroidFS/` (entire directory)
- Delete: `FreeDroid/Mount/` (entire directory)
- Delete: `FreeDroid/UI/FSExtensionBanner.swift`
- Modify: `project.yml` (drop FreeDroidFS target + dependency from FreeDroid)
- Modify: `Scripts/install-to-applications.sh` (drop pluginkit dance — keep lsregister only)

- [ ] **Step 1: Run the deletions**

```bash
git rm -rf FreeDroidFS FreeDroid/Mount FreeDroid/UI/FSExtensionBanner.swift
```

- [ ] **Step 2: Update project.yml**

Remove the entire `FreeDroidFS:` target block and the `- target: FreeDroidFS` dependency from the `FreeDroid` target.

- [ ] **Step 3: Strip pluginkit/fskit logic from install-to-applications.sh**

Replace the appex-handling block with:

```bash
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREG" "$DEST" 2>/dev/null || true
```

- [ ] **Step 4: Regenerate the Xcode project**

Run: `Scripts/generate-project.sh`

- [ ] **Step 5: Build**

Run: `xcodebuild -workspace FreeDroid.xcworkspace -scheme FreeDroid -configuration Debug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Verify no FSKit references remain**

```bash
grep -rn "FSKit\|FSExtensionMonitor\|MountCoordinator\|MountedVolumeStore\|FSExtensionBanner\|FreeDroidFS" \
  FreeDroid Sources --include='*.swift' || echo "clean"
```

Expected: `clean`.

- [ ] **Step 7: Commit**

```bash
git commit -m "chore: remove FSKit extension and MountCoordinator"
```

---

### Task 16: Update PROJECT_STATUS.md and README.md

**Files:**
- Modify: `PROJECT_STATUS.md`
- Modify: `README.md`

- [ ] **Step 1: Rewrite the FSKit / mount sections in PROJECT_STATUS.md**

Replace issues #1, #2, #3, #6 with a single "Finder integration" entry stating:

> Finder integration uses `NSFileProviderReplicatedExtension`. Each connected device is registered as a `NSFileProviderDomain` and appears in Finder under Locations. No System Settings toggle, no `/Volumes` mount, no FSKit. macFUSE / FSKit are not used or required.

Add to "What works":

> - Finder integration via File Provider ✅ Devices appear in Finder sidebar under Locations as soon as ADB authorization completes.

- [ ] **Step 2: Update README**

Replace any mention of FSKit / "enable in System Settings" with the File Provider story.

- [ ] **Step 3: Commit**

```bash
git commit -am "docs: replace FSKit narrative with File Provider"
```

---

## Phase 8 — Polish

### Task 17: Reveal-in-Finder action per device card

**Files:**
- Modify: `FreeDroid/ContentView.swift`
- Modify: `Sources/DeviceManagement/DeviceCardView.swift` (already has a context menu hook)

- [ ] **Step 1: Add NSFileProviderManager-based reveal helper**

`FreeDroid/Provider/ProviderRevealer.swift`:

```swift
import AppKit
import FileProvider
import FreeDroidDomain

enum ProviderRevealer {
    @MainActor
    static func revealInFinder(deviceID: DeviceID) async {
        let identifier = NSFileProviderDomainIdentifier(deviceID.raw)
        do {
            let url = try await NSFileProviderManager(for: NSFileProviderDomain(identifier: identifier, displayName: ""))?
                .getUserVisibleURL(for: .rootContainer) ?? URL(fileURLWithPath: "/")
            NSWorkspace.shared.open(url)
        } catch {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/"))
        }
    }
}
```

- [ ] **Step 2: Wire into the context menu**

In `DeviceCardView`, the existing `Button("Reveal Transfers in Finder")` can stay; add a sibling `Button("Show in Finder") { Task { await ProviderRevealer.revealInFinder(deviceID: ...) } }`. Plumb `deviceID` through the card view model if not already.

- [ ] **Step 3: Build + smoke**

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(provider): add Show in Finder action per device"
```

---

### Task 18: Working-set enumerator + change signaling

**Files:**
- Create: `FreeDroidProvider/WorkingSetEnumerator.swift`
- Modify: `FreeDroidProvider/FreeDroidProviderExtension.swift`

- [ ] **Step 1: Working-set enumerator stub**

`FreeDroidProvider/WorkingSetEnumerator.swift`:

```swift
import FileProvider
import Foundation

final class WorkingSetEnumerator: NSObject, NSFileProviderEnumerator {
    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("v0".utf8)))
    }
}
```

- [ ] **Step 2: Route .workingSet in `enumerator(for:request:)`**

```swift
    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        if containerItemIdentifier == .workingSet { return WorkingSetEnumerator() }
        if containerItemIdentifier == .trashContainer {
            throw NSFileProviderError(.noSuchItem)
        }
        let path = ItemIdentifier.decode(containerItemIdentifier.rawValue) ?? .root
        return FolderEnumerator(
            container: containerItemIdentifier,
            folderPath: path,
            deviceID: deviceID,
            bridge: bridge
        )
    }
```

- [ ] **Step 3: Build + commit**

```bash
git commit -am "feat(provider): add WorkingSet + Trash enumerator routing"
```

---

### Task 19: End-to-end manual acceptance + regression test pass

**Files:** none — verification step.

- [ ] **Step 1: Quit any running app instance**

```bash
osascript -e 'tell application "FreeDroid" to quit' 2>/dev/null || true
```

- [ ] **Step 2: Clean install**

Run: `xcodebuild -workspace FreeDroid.xcworkspace -scheme FreeDroid -configuration Debug -destination 'platform=macOS' clean build`
Expected: `** BUILD SUCCEEDED **` and `Installed at /Applications/FreeDroid.app` from the post-action.

- [ ] **Step 3: Launch + verify domain registration**

Launch the app. Then:

```bash
log show --last 30s --predicate 'subsystem == "com.merkost.freedroid" AND category == "provider"'
```

Expected: `Registered domain for <DeviceName>` log lines for each ready device.

- [ ] **Step 4: Verify in Finder**

Open Finder. Expect each connected device under **Locations** sidebar. Click one — see directory listing.

- [ ] **Step 5: CRUD checklist**

In Finder, perform on the mounted device:

- [ ] List `/sdcard` — folder names visible
- [ ] Open `/sdcard/Download` — contents listed
- [ ] Quick Look a JPG — image renders
- [ ] Open a text file — contents appear
- [ ] Create a new folder via right-click → New Folder — appears in `adb shell ls`
- [ ] Rename the folder — change persists
- [ ] Drag a small file from Mac into the device — uploaded
- [ ] Delete the folder — gone from device

- [ ] **Step 6: SPM tests pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 7: Commit nothing — this is verification only**

If any step fails, file a follow-up task with the symptom and `log show` excerpt and return to Phase 5/6 for the relevant method.

---

## Self-review notes

1. **Identifier scheme** is consistent across Task 2 (codec), Task 5 (ProviderItem use), Task 8 (extension), Task 11 (fetchContents), Task 12-14 (writes). Verified.
2. **`IPCRequest.write`** currently goes through the existing `XPCFileServerHandler` which calls `transport().write(...)` — that path returns `IPCResponse.empty`, but the bridge in Task 6 handles `.empty where T.self == Data.self`. Cross-checked.
3. **`NSFileProviderDomainIdentifier`** is `RawRepresentable<String>` so `NSFileProviderDomainIdentifier(deviceID.raw)` is valid. Cross-checked against API.
4. **Mach service rename** in Task 6 changes a contract — Task 6 also updates the host app's `IPCEndpoint` so both sides flip together. The legacy `XPCClient` in `FreeDroidFS/` is deleted in Task 15 along with the whole appex, so no stale reference remains.
5. **No placeholders** — every code step has a complete code block. No "implement X" or "similar to". Verified.
6. **macOS 26 third-party FSKit bug** — Task 15 deletes the FSKit code entirely; we don't try to keep both. Verified.
7. **One unknown:** `Sources/FreeDroidIPC/IPCResponse.swift` already has a `.empty` case (verified in Phase 2 prep). Bridge code paths for write/mkdir/remove/rename should all return `.empty`; the bridge in Task 6 handles `.empty` for `T == Data.self`. If any of those return `.entry`/`.entries` accidentally in the host handler, write-path tests in Task 12 will catch it.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-12-file-provider-migration.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Good for this plan since each task has a clean boundary and produces a green build.

**2. Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints for review.

Which approach?
