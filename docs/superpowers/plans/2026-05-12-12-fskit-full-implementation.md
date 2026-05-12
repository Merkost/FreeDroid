# FreeDroid Plan #12 — FreeDroidFS Full Implementation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take `FreeDroidFS` from "compiles, bundle produced, mount stubbed" (current state from Plan #10) to "Android devices appear as real volumes in Finder with read/write/list/rename/delete working end-to-end." Includes: securing the FSKit entitlement, fleshing out every FSKit operation against real Apple APIs, hardening the XPC bridge, adding FSItem caching for Finder responsiveness, real-device manual verification scripts, and a fallback path if Apple denies the entitlement.

**Architecture:** No structural changes to the codebase shape. The two-process model from Plan #10 stays (`FreeDroid.app` ↔ `FreeDroidFS.fskitmodule` over XPC). What changes is the inside of every FSKit callback — from skeletal pass-through to a complete, cache-aware, errno-correct implementation. Plus the entitlement, signing, and verification scaffolding to actually load it on real hardware.

**Tech Stack:** FSKit (macOS 15.4+), XPC via `NSXPCConnection`, IOKit, real Android device for verification.

---

## Critical prerequisite

**Apple FSKit entitlement** (`com.apple.developer.fskit.fsmodule`) must be granted to your Developer Team ID. Without it, `fskitd` will refuse to load the extension regardless of code quality.

Submit the request via Apple Developer Support **before starting Task 5**. Approval typically takes 1–3 weeks. Use this template:

> Subject: Request: com.apple.developer.fskit.fsmodule entitlement
>
> We are building FreeDroid, a free open-source macOS application that mounts USB-connected Android devices as native Finder volumes via FSKit. The application is non-commercial, source-available under MIT, and intended for end-users on macOS 15.4+. We request the `com.apple.developer.fskit.fsmodule` entitlement for Team ID `<YOUR_TEAM_ID>` to ship signed builds via direct distribution (notarized DMG, Sparkle updates). The FSKit module is named `FreeDroidFS.fskitmodule`. Repository: <repo URL>. We would appreciate review at your convenience.

While the entitlement is in flight, every task in this plan can be implemented and validated against a development build via the **provisional path** (Task 12). Apple's `fskitd` will refuse to load the unsigned extension, but the code can still be exercised via the local-test harness.

---

## File structure

```
FreeDroidFS/
├── Info.plist                                          modify
├── FreeDroidFS.entitlements                            modify
├── FreeDroidFSModule.swift                             modify — full FSUnaryFileSystem
├── FreeDroidVolume.swift                               modify — full FSVolume + caching
├── FreeDroidItem.swift                                 modify — extended state
├── FreeDroidItemCache.swift                            create — path→FSItem map
├── XPCClient.swift                                     modify — reconnect, batching
├── ErrnoMapping.swift                                  modify — extended cases
├── VolumeIdentifierMint.swift                          create — stable per-device UUIDs
├── DirectoryEnumerator.swift                           create — paginated listing
└── FSKitLogger.swift                                   create — os.Logger wrapper

FreeDroid/IPC/
├── XPCFileServer.swift                                 modify — connection lifecycle
├── XPCFileServerHandler.swift                          modify — batched ops, cancellation
└── XPCConnectionRegistry.swift                         modify — per-device endpoints

FreeDroid/Mount/
├── MountCoordinator.swift                              create — orchestrates FSResource lifecycle
└── MountedVolumeStore.swift                            create — persists device↔URL bindings

Sources/FreeDroidIPC/
└── IPCRequest.swift                                    modify — add batched & cancelable ops

Scripts/
├── install-dev-fskit.sh                                create — local install + load helper
└── verify-fskit-mount.sh                               create — end-to-end manual checks
```

---

## Task 1 — Volume identifier mint and FSItem cache

**Goal:** Stable `FSVolume.Identifier` per device serial across remounts so Finder, Spotlight, and aliases survive disconnects. FSItem cache so directory revisits don't re-XPC.

**Files:**
- Create: `FreeDroidFS/VolumeIdentifierMint.swift`
- Create: `FreeDroidFS/FreeDroidItemCache.swift`

- [ ] **Step 1: Implement `VolumeIdentifierMint`**

Write `FreeDroidFS/VolumeIdentifierMint.swift`:

```swift
import Foundation
import FSKit

enum VolumeIdentifierMint {
    static func identifier(for deviceSerial: String) -> FSVolume.Identifier {
        let namespace = UUID(uuidString: "8F4F9C7D-7B7E-4F1C-9D2F-31E2E12B7E08")!
        let combined = "\(namespace.uuidString):\(deviceSerial)"
        let digest = combined.data(using: .utf8)!.sha256Prefix16()
        var bytes = [UInt8](digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return FSVolume.Identifier(uuid: uuid)
    }
}

private extension Data {
    func sha256Prefix16() -> Data {
        let digest = sha256()
        return digest.prefix(16)
    }

    func sha256() -> Data {
        import CryptoKit
        let hash = SHA256.hash(data: self)
        return Data(hash)
    }
}
```

Note: the inline `import CryptoKit` is invalid Swift; move that to the top of the file. Use `CryptoKit.SHA256` for the digest.

- [ ] **Step 2: Implement `FreeDroidItemCache`**

Write `FreeDroidFS/FreeDroidItemCache.swift`:

```swift
import Foundation
import FreeDroidDomain

actor FreeDroidItemCache {
    private struct CacheEntry {
        let item: FreeDroidItem
        let storedAt: ContinuousClock.Instant
    }

    private let ttl: Duration
    private let clock = ContinuousClock()
    private var entries: [RemotePath: CacheEntry] = [:]

    init(ttl: Duration = .seconds(45)) {
        self.ttl = ttl
    }

    func get(_ path: RemotePath) -> FreeDroidItem? {
        guard let entry = entries[path] else { return nil }
        guard clock.now - entry.storedAt <= ttl else {
            entries[path] = nil
            return nil
        }
        return entry.item
    }

    func put(_ path: RemotePath, _ item: FreeDroidItem) {
        entries[path] = CacheEntry(item: item, storedAt: clock.now)
    }

    func invalidate(_ path: RemotePath) {
        entries[path] = nil
        let prefix = path.raw + "/"
        for key in entries.keys where key.raw.hasPrefix(prefix) {
            entries[key] = nil
        }
    }

    func invalidateAll() {
        entries.removeAll()
    }
}
```

- [ ] **Step 3: Build**

```bash
Scripts/generate-project.sh
xcodebuild -workspace FreeDroid.xcworkspace -scheme FreeDroid -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): add stable volume identifier mint and FSItem TTL cache"
```

---

## Task 2 — Directory enumerator with pagination

**Goal:** Finder requests directory contents via cursor-based iteration. A bare `enumerateDirectory` that returns the full list breaks on folders with thousands of files. Implement a `DirectoryEnumerator` that batches in chunks of 200 and respects `FSDirectoryCookie` for resume.

**Files:**
- Create: `FreeDroidFS/DirectoryEnumerator.swift`

- [ ] **Step 1: Implement the enumerator**

Write `FreeDroidFS/DirectoryEnumerator.swift`:

```swift
import Foundation
import FSKit
import FreeDroidDomain

actor DirectoryEnumerator {
    private let directory: FreeDroidItem
    private let client: XPCClient
    private var allEntries: [RemoteEntry] = []
    private var fetched = false

    init(directory: FreeDroidItem, client: XPCClient) {
        self.directory = directory
        self.client = client
    }

    func next(cookie: FSDirectoryCookie, pageSize: Int = 200) async throws -> (items: [FSItem], nextCookie: FSDirectoryCookie?) {
        try await fetchOnce()
        let startIndex = cookie.intValue
        let endIndex = min(startIndex + pageSize, allEntries.count)
        guard startIndex < allEntries.count else {
            return ([], nil)
        }
        let slice = allEntries[startIndex..<endIndex]
        let items = slice.map { FreeDroidItem(deviceID: directory.deviceID, entry: $0) }
        let next = endIndex < allEntries.count ? FSDirectoryCookie(intValue: endIndex) : nil
        return (items, next)
    }

    private func fetchOnce() async throws {
        guard !fetched else { return }
        allEntries = try await client.send(
            .list(deviceID: directory.deviceID, path: directory.entry.path),
            expecting: [RemoteEntry].self
        )
        fetched = true
    }
}

private extension FSDirectoryCookie {
    var intValue: Int {
        Int(bitPattern: UInt(truncatingIfNeeded: rawValue))
    }

    init(intValue: Int) {
        self.init(rawValue: UInt64(bitPattern: Int64(intValue)))
    }
}
```

> The exact `FSDirectoryCookie` API may differ in your SDK; consult `FSKit.framework` headers for the canonical initializer. The above is a starting shape — adapt to the real type signature.

- [ ] **Step 2: Build and commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): add paginated DirectoryEnumerator"
```

---

## Task 3 — Wire FSItem cache and enumerator into FreeDroidVolume

**Files:**
- Modify: `FreeDroidFS/FreeDroidVolume.swift`

- [ ] **Step 1: Inject cache + use enumerator**

Add a `let cache = FreeDroidItemCache()` stored property. Replace ad-hoc `enumerateDirectory` body with one that uses `DirectoryEnumerator`:

```swift
func enumerateDirectory(_ item: FSItem, startingAt cookie: FSDirectoryCookie) async throws -> (items: [FSItem], next: FSDirectoryCookie?) {
    guard let dir = item as? FreeDroidItem else { return ([], nil) }
    let enumerator = DirectoryEnumerator(directory: dir, client: client)
    return try await enumerator.next(cookie: cookie)
}
```

Every operation that mutates a path (`createItem`, `removeItem`, `renameItem`, `writeFile`) should call `await cache.invalidate(parentPath)` afterward.

`lookupItem` uses the cache first:

```swift
func lookupItem(named name: String, in parent: FSItem) async throws -> FSItem? {
    guard let parent = parent as? FreeDroidItem else { return nil }
    let path = parent.entry.path.appending(name)
    if let cached = await cache.get(path) {
        return cached
    }
    do {
        let entry: RemoteEntry = try await client.send(.stat(deviceID: parent.deviceID, path: path), expecting: RemoteEntry.self)
        let item = FreeDroidItem(deviceID: parent.deviceID, entry: entry)
        await cache.put(path, item)
        return item
    } catch TransportError.notFound {
        return nil
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): cache-backed lookup and paginated enumeration in FreeDroidVolume"
```

---

## Task 4 — Robust XPCClient with reconnect

**Files:**
- Modify: `FreeDroidFS/XPCClient.swift`

The current client fails permanently if the parent app restarts (e.g. during dev iteration). Add automatic reconnection.

- [ ] **Step 1: Make `proxy()` async-throws and retry once on invalidation**

```swift
actor XPCClient {
    private var connection: NSXPCConnection?
    private var generation: Int = 0

    func send<T>(_ request: IPCRequest, expecting: T.Type) async throws -> T where T: Decodable {
        for attempt in 0..<2 {
            do {
                return try await sendOnce(request, expecting: expecting)
            } catch let error as TransportError where attempt == 0 && error == .notConnected {
                invalidate()
            }
        }
        throw TransportError.notConnected
    }

    private func sendOnce<T>(_ request: IPCRequest, expecting: T.Type) async throws -> T where T: Decodable {
        let proxy = try await proxyOrThrow()
        let payload = try IPCCoder.encoder.encode(request)
        let responseData = await proxy.send(payload)
        let response = try IPCCoder.decoder.decode(IPCResponse.self, from: responseData)
        return try decode(response, expecting: expecting)
    }

    private func proxyOrThrow() async throws -> XPCFileServerProtocol {
        if let connection {
            return connection.remoteObjectProxy as! XPCFileServerProtocol
        }
        let new = NSXPCConnection(machServiceName: IPCEndpoint.machServiceName, options: [])
        new.remoteObjectInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
        new.invalidationHandler = { [weak self] in
            Task { await self?.invalidate() }
        }
        new.interruptionHandler = { [weak self] in
            Task { await self?.invalidate() }
        }
        new.resume()
        connection = new
        generation += 1
        return new.remoteObjectProxy as! XPCFileServerProtocol
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func decode<T>(_ response: IPCResponse, expecting: T.Type) throws -> T where T: Decodable {
        // existing decoding logic
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): XPCClient auto-reconnect across app restarts"
```

---

## Task 5 — App-side XPC server hardening

**Files:**
- Modify: `FreeDroid/IPC/XPCFileServer.swift`
- Modify: `FreeDroid/IPC/XPCFileServerHandler.swift`

- [ ] **Step 1: Audit connections**

In `XPCFileServer.listener(_:shouldAcceptNewConnection:)`, verify the incoming connection's audit token comes from our own FSKit extension. Reject foreign connections:

```swift
func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
    let pid = newConnection.processIdentifier
    guard FreeDroidFSAuditor.isExtensionPID(pid) else {
        return false
    }
    newConnection.exportedInterface = NSXPCInterface(with: XPCFileServerProtocol.self)
    newConnection.exportedObject = XPCFileServerExportedObject(handler: handler)
    newConnection.resume()
    return true
}
```

`FreeDroidFSAuditor.isExtensionPID` reads the process's code-signing requirements and verifies the Team ID + bundle identifier matches `com.merkost.freedroid.FreeDroidFS`. For dev builds skip if signing identity is ad-hoc.

- [ ] **Step 2: Add a heartbeat to detect dead extension**

Add `func ping() async -> Bool` to the XPC protocol. The app pings every 30s; if the extension stops responding, invalidate the in-app `DeviceRegistry`'s mount records so the UI shows the device as unmounted.

- [ ] **Step 3: Build and commit**

```bash
git add FreeDroid Sources/FreeDroidIPC
git commit -m "feat(ipc): audit connections and heartbeat-based extension liveness"
```

---

## Task 6 — Mount coordinator and persistent volume store

**Files:**
- Create: `FreeDroid/Mount/MountCoordinator.swift`
- Create: `FreeDroid/Mount/MountedVolumeStore.swift`

- [ ] **Step 1: `MountedVolumeStore` persists device-serial ↔ volume-URL bindings**

Write `FreeDroid/Mount/MountedVolumeStore.swift`:

```swift
import Foundation
import FreeDroidDomain

actor MountedVolumeStore {
    private let url: URL
    private var snapshot: [DeviceID: URL]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = support.appendingPathComponent("FreeDroid", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.url = folder.appendingPathComponent("mounted-volumes.json")
        if let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([DeviceID: URL].self, from: data) {
            self.snapshot = map
        } else {
            self.snapshot = [:]
        }
    }

    func record(_ deviceID: DeviceID, mountedAt mountURL: URL) async {
        snapshot[deviceID] = mountURL
        try? persist()
    }

    func forget(_ deviceID: DeviceID) async {
        snapshot[deviceID] = nil
        try? persist()
    }

    func mountURL(for deviceID: DeviceID) async -> URL? {
        snapshot[deviceID]
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }
}
```

- [ ] **Step 2: `MountCoordinator` orchestrates mount and unmount**

Write `FreeDroid/Mount/MountCoordinator.swift`:

```swift
import Foundation
import FSKit
import FreeDroidDomain
import os.log

private let mountLogger = Logger(subsystem: "com.merkost.freedroid", category: "mount")

@MainActor
final class MountCoordinator {
    private let store = MountedVolumeStore()
    private let manager = FSFileSystemManager.shared

    func mountIfNeeded(_ device: Device) async {
        guard device.connectionState == .ready else { return }
        if let existing = await store.mountURL(for: device.id), FileManager.default.fileExists(atPath: existing.path) {
            return
        }
        do {
            let url = try await performMount(device)
            await store.record(device.id, mountedAt: url)
            mountLogger.info("Mounted \(device.displayName, privacy: .public) at \(url.path, privacy: .public)")
        } catch {
            mountLogger.error("Mount failed for \(device.displayName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func unmount(_ deviceID: DeviceID) async {
        guard let url = await store.mountURL(for: deviceID) else { return }
        do {
            try await performUnmount(url)
            await store.forget(deviceID)
            mountLogger.info("Unmounted \(url.path, privacy: .public)")
        } catch {
            mountLogger.error("Unmount failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func performMount(_ device: Device) async throws -> URL {
        // FSKit-specific call. The actual API to request mounting from the app side
        // varies — refer to FSKit framework headers. The current macOS 15.4 SDK
        // exposes FSClient + FSResource registration; the precise mount-trigger
        // entry point should be discovered via `xcrun --show-sdk-path` and
        // `FSKit.framework/Headers`.
        throw TransportError.unsupported(reason: "mount-trigger API discovery pending")
    }

    private func performUnmount(_ url: URL) async throws {
        // umount(2) equivalent or `FSFileSystemManager.unmount(...)`
        throw TransportError.unsupported(reason: "unmount API discovery pending")
    }
}
```

> The mount-trigger and unmount APIs need to be discovered against the real FSKit headers for macOS 15.4+. Once entitlement is in place, complete this in Task 7.

- [ ] **Step 3: Build and commit**

```bash
git add FreeDroid
git commit -m "feat(mount): persistent volume store and coordinator skeleton"
```

---

## Task 7 — Complete mount/unmount against FSKit APIs

**Files:**
- Modify: `FreeDroid/Mount/MountCoordinator.swift`
- Modify: `FreeDroidFS/FreeDroidFSModule.swift`

- [ ] **Step 1: Discover the real FSKit mount API**

Inspect the SDK:

```bash
SDK=$(xcrun --sdk macosx --show-sdk-path)
find "$SDK/System/Library/Frameworks/FSKit.framework" -name "*.h" | head -20
find "$SDK/System/Library/Frameworks/FSKit.framework" -name "*.swiftinterface" | xargs grep -l "mount\|register\|FSResource\|FSClient" 2>/dev/null
```

Read the headers and Swift interfaces. The canonical pattern in macOS 15.4 SDK is roughly:

- `FSClient.shared` exists and exposes `fetchInstalledExtensions` (already used)
- Mounting is **fskitd-driven**, not app-driven. The app registers a resource description; `fskitd` calls the extension's `probeResource` + `loadResource` and performs the actual `mount()` system call.
- The app's responsibility is to inform `fskitd` (via XPC to a system service) that a new resource exists. This may be via `FSResource` registration APIs in `FSKit.framework`.

Update `performMount` to use whatever the real API is. If the API is `FSFileSystemManager.shared.mount(_ resource: FSResource, ...)` adapt; if it's `FSClient.shared.register(_:)`, adapt; if it's deferred to a system daemon via a `LaunchAgent`, integrate that.

- [ ] **Step 2: Update `FreeDroidFSModule.probeResource` and `loadResource`**

Make `probeResource(resource:)` actually inspect `resource.url` and decide whether this extension supports it. Use the URL scheme `freedroid://` (registered in Info.plist as a supported scheme) and the host (device serial). Reject anything else.

`loadResource(resource:options:)` extracts the device serial from the URL, then constructs `FreeDroidVolume` with that serial. The `client` is shared across all volumes.

- [ ] **Step 3: Register URL scheme in extension Info.plist**

`FreeDroidFS/Info.plist` — add:

```xml
<key>FSResourceSchemes</key>
<array>
    <string>freedroid</string>
</array>
```

(Exact key name may differ — verify against FSKit headers. The intent: the extension declares which `FSResource` URL schemes it can `probe` and `load`.)

- [ ] **Step 4: Build and commit**

```bash
git add FreeDroid FreeDroidFS
git commit -m "feat(fskit): real mount/unmount via FSKit APIs"
```

---

## Task 8 — Read attributes and file ops correctness

**Files:**
- Modify: `FreeDroidFS/FreeDroidVolume.swift`
- Modify: `FreeDroidFS/FreeDroidItem.swift`

- [ ] **Step 1: POSIX attribute synthesis**

In `FreeDroidItem`, expose `attributes: FSItem.Attributes` synthesized from `RemoteEntry`:

```swift
override var attributes: FSItem.Attributes {
    var attrs = FSItem.Attributes()
    attrs.fileType = entry.kind == .directory ? .directory : .regular
    attrs.fileSize = UInt64(entry.sizeBytes ?? 0)
    attrs.modificationDate = entry.modifiedAt ?? Date(timeIntervalSince1970: 0)
    attrs.creationDate = attrs.modificationDate
    attrs.posixPermissions = entry.kind == .directory ? 0o755 : 0o644
    attrs.ownerID = NSUserName().hash & 0xFFFF
    attrs.groupID = attrs.ownerID
    return attrs
}
```

(Exact `FSItem.Attributes` API depends on SDK — adapt accordingly.)

- [ ] **Step 2: Correct error mapping**

In `ErrnoMapping.swift`, ensure every `TransportError` case maps to the most accurate POSIX errno:

| TransportError | errno | Rationale |
|---|---|---|
| `.notConnected` | `ENODEV` | Device temporarily gone |
| `.unauthorized` | `EACCES` | Permission denied |
| `.timeout` | `ETIMEDOUT` | Operation timed out |
| `.ioFailure` | `EIO` | Generic I/O failure |
| `.notFound` | `ENOENT` | No such file or directory |
| `.alreadyExists` | `EEXIST` | File exists |
| `.unsupported` | `ENOTSUP` | Operation not supported |
| `.cancelled` | `ECANCELED` | Operation cancelled |

Wrap every FSKit operation in `do/catch` and convert to `NSError(domain: NSPOSIXErrorDomain, code: Int(errno))`.

- [ ] **Step 3: Build and commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): synthesize POSIX attributes and complete errno mapping"
```

---

## Task 9 — `.partial` shadow writes and `.FreeDroid/Trash` deletes

**Files:**
- Modify: `FreeDroidFS/FreeDroidVolume.swift`

Per spec §7.3:
- Writes go to `<path>.partial` first, then atomic-rename at completion.
- Deletes move to `.FreeDroid/Trash/` first; sweep entries older than 24h via a periodic task.

- [ ] **Step 1: Shadow-write `writeFile`**

In `writeFile`, write to `<parent>/<name>.partial`. On final write, send a `rename` IPC to move it into place. On error, send a `remove` to clean up the partial.

- [ ] **Step 2: Trash-on-delete `removeItem`**

In `removeItem`, instead of `remove`, send `mkdir(.FreeDroid/Trash)` (idempotent), then `rename(<path>, .FreeDroid/Trash/<uuid>-<name>)`.

- [ ] **Step 3: Periodic trash sweep**

In `FreeDroidFSModule` add a `Task` that wakes every hour and removes entries in `.FreeDroid/Trash` older than 24h via the `remove` IPC.

- [ ] **Step 4: Build and commit**

```bash
git add FreeDroidFS
git commit -m "feat(fskit): shadow-write partial files and trash-bucket deletes"
```

---

## Task 10 — Local dev signing script

**Files:**
- Create: `Scripts/install-dev-fskit.sh`

Even before Apple grants the entitlement, you can run a dev build with the entitlement declared and ad-hoc signed — `fskitd` will refuse to load it, but the local-test harness can exercise the XPC paths.

- [ ] **Step 1: Write the script**

Write `Scripts/install-dev-fskit.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
APP_PATH="$REPO_ROOT/build/install/FreeDroid.app"

cd "$REPO_ROOT"

rm -rf "$REPO_ROOT/build/install"
mkdir -p "$REPO_ROOT/build/install"

xcodebuild \
    -workspace FreeDroid.xcworkspace \
    -scheme FreeDroid \
    -destination 'platform=macOS' \
    -configuration Debug \
    -derivedDataPath "$REPO_ROOT/build/dev" \
    CODE_SIGNING_ALLOWED=NO \
    build

cp -R "$REPO_ROOT/build/dev/Build/Products/Debug/FreeDroid.app" "$APP_PATH"

codesign --force --deep --sign - \
    --entitlements "$REPO_ROOT/FreeDroid/FreeDroid.entitlements" \
    "$APP_PATH"

EXT_PATH="$APP_PATH/Contents/PlugIns/FreeDroidFS.fskitmodule"
codesign --force --sign - \
    --entitlements "$REPO_ROOT/FreeDroidFS/FreeDroidFS.entitlements" \
    "$EXT_PATH"

echo "Installed at $APP_PATH"
echo "Run: open '$APP_PATH'"
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x Scripts/install-dev-fskit.sh
git add Scripts
git commit -m "chore(fskit): local dev signing helper for FSKit entitlement testing"
```

---

## Task 11 — End-to-end verification script

**Files:**
- Create: `Scripts/verify-fskit-mount.sh`

Manual verification helper for someone with the entitlement in place.

- [ ] **Step 1: Write the script**

Write `Scripts/verify-fskit-mount.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "FreeDroid FSKit verification"
echo "============================"
echo

echo "1) Checking installed FSKit modules…"
SYSTEM_EXTENSIONS=$(systemextensionsctl list 2>/dev/null | grep -i freedroid || true)
if [ -z "$SYSTEM_EXTENSIONS" ]; then
    echo "  (none — module is not registered yet)"
else
    echo "$SYSTEM_EXTENSIONS"
fi
echo

echo "2) Checking USB devices via system_profiler…"
USB_ANDROID=$(system_profiler SPUSBDataType -json 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
def walk(item):
    if isinstance(item, dict):
        vid = item.get('vendor_id', '')
        if any(v in vid for v in ['0x18d1', '0x04e8', '0x22b8', '0x2717', '0x2a70', '0x12d1']):
            print(item.get('_name', '<unnamed>'), vid)
        for v in item.values():
            walk(v)
    elif isinstance(item, list):
        for v in item: walk(v)
walk(data)
")
echo "$USB_ANDROID"
echo

echo "3) Checking ADB visibility…"
ADB="$PWD/Sources/FreeDroidADB/adb"
if [ -x "$ADB" ]; then
    "$ADB" devices -l
else
    echo "  (adb binary not found at $ADB)"
fi
echo

echo "4) Checking mounted volumes…"
mount | grep -i freedroid || echo "  (no FreeDroid volumes mounted)"
echo

echo "5) Checking fskitd logs (last 1 minute)…"
log show --predicate 'subsystem == "com.apple.fskit"' --last 1m 2>/dev/null | tail -20 || \
    log show --predicate 'process == "fskitd"' --last 1m 2>/dev/null | tail -20
echo
echo "Done."
```

- [ ] **Step 2: Make executable, run once, commit**

```bash
chmod +x Scripts/verify-fskit-mount.sh
Scripts/verify-fskit-mount.sh
git add Scripts
git commit -m "chore(fskit): end-to-end mount verification helper"
```

---

## Task 12 — Provisional path (without Apple entitlement)

While waiting for Apple's approval, set up an alternative mount path using File Provider Extension (FPX). This is `FPXMountStrategy` from the spec §4.4.

This task is optional — only execute if entitlement approval is delayed beyond an acceptable window.

**Files:**
- Create: `FreeDroidFPX/` target (similar structure to `FreeDroidFS`)
- Modify: `Sources/FreeDroidDomain/Mount/MountStrategy.swift`

- [ ] **Step 1: Add `FPXMountStrategy` per spec §4.4**

The File Provider Extension API works without special entitlement and ships through the Mac App Store. UX is cloud-storage-like (sidebar item, on-demand fetch). Map FreeDroid's `FileRepository` operations onto `NSFileProviderReplicatedExtension` callbacks.

- [ ] **Step 2: Wire `MountCoordinator` to pick the strategy at runtime**

```swift
let strategy: any MountStrategy = FSKitMountStrategy.canLoad()
    ? FSKitMountStrategy()
    : FPXMountStrategy()
```

`canLoad()` checks the installed extensions via `FSClient.shared.fetchInstalledExtensions` and confirms our module is present.

- [ ] **Step 3: Build and commit**

```bash
git add FreeDroidFPX FreeDroid Sources/FreeDroidDomain
git commit -m "feat(mount): add FPX mount strategy as entitlement-free fallback"
```

---

## Task 13 — Final manual verification with real device

This is a manual milestone, not an automated test.

- [ ] **Step 1: Sign with real Developer ID and FSKit entitlement**

Once Apple has approved `com.apple.developer.fskit.fsmodule`:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
Scripts/build-release.sh 0.10.0-dev
```

- [ ] **Step 2: Install the produced app**

```bash
cp -R build/release/FreeDroid.app /Applications/
sudo systemextensionsctl reset
```

Open the app once so macOS registers the extension. Approve in System Settings → Privacy & Security.

- [ ] **Step 3: Plug in a phone with USB debugging enabled**

```bash
Scripts/verify-fskit-mount.sh
```

Expected output: `mount | grep freedroid` shows a line like `freedroidfs on /Volumes/<Device Name>`. `ls /Volumes/<Device Name>` lists `DCIM`, `Music`, `Pictures`, etc.

- [ ] **Step 4: Exercise file ops**

- Open `/Volumes/<Device Name>/DCIM/Camera` in Finder — photos appear with thumbnails
- Drag a small photo from phone to Desktop — file copies correctly
- Drag a file from Mac to phone — appears on phone
- Right-click → Get Info → check size, mod date
- Rename a file via Finder — succeeds
- Move to trash — file lands in `.FreeDroid/Trash` on the device
- Unplug → volume cleanly disappears in Finder; replug → reappears with same UUID

- [ ] **Step 5: Performance budget verification**

Per spec §12.3:

- Cold mount + first directory shown: < 800ms — time with `time ls /Volumes/<Device Name>` from clean mount
- `listdir` of 1000-file folder cached: < 50ms — `time ls /Volumes/<Device Name>/DCIM/Camera` (second invocation)
- `listdir` of 1000-file folder cold ADB: < 1s — first invocation with empty cache
- Cmd+C / Cmd+V single 50MB file: < 5s — manual timing
- UI frame time during transfer: 60fps — Instruments → Time Profiler

Mark any budget violations as follow-up issues in `docs/known-issues.md`.

- [ ] **Step 6: Document any quirks**

If specific devices misbehave, add entries to `docs/mtp-quirks.md` (or `docs/fskit-quirks.md`). Pin the volume identifier UUID for known devices to maintain alias compatibility.

---

## Done When

- `com.apple.developer.fskit.fsmodule` entitlement granted and embedded.
- Signed/notarized build of `FreeDroid.app` containing `FreeDroidFS.fskitmodule`.
- Plugging an authorized Android phone results in `/Volumes/<device>` appearing in Finder within 3 seconds.
- Read, write, list, rename, delete all functional from Finder.
- Trash semantics: deletes land in `.FreeDroid/Trash` and auto-purge after 24h.
- Atomic writes: `.partial` shadow with rename-on-completion; partial files cleaned on interrupt.
- FSItem cache reduces repeat listings to <50ms.
- Unplug cleanly unmounts; replug remounts at same UUID; aliases survive.
- All performance budgets from spec §12.3 met.

## Self-Review

- Spec §4.1 (two-process model) → preserved.
- Spec §4.4 (MountStrategy abstraction) → FSKit primary, FPX fallback (Task 12).
- Spec §7 (FSKit lifecycle, callbacks, safety) → Tasks 3, 7, 8, 9.
- Spec §7.4 (caching) → Tasks 1, 3.
- Spec §9.3 (cancellation, retry, logging) → XPCClient retry (Task 4), logger usage.
- Spec §11.4 (signing & notarization) → Task 13 + existing Plan #11 release pipeline.
- Spec §12.3 (performance budgets) → Task 13 step 5.
- Spec §13 risks (entitlement, libmtp build, MTP quirks) → all covered, FPX fallback for entitlement risk.
