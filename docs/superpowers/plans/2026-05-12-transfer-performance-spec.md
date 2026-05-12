# Transfer Performance Upgrade — Full Spec

**Companion doc:** [`2026-05-12-transfer-performance.md`](./2026-05-12-transfer-performance.md) (analysis & rationale).
**Goal:** bring FreeDroid transfer speed to macDroid parity (or better) across all paths — Finder File Provider, in-app transfer queue, multi-file copy, Quick Look re-fetch.
**Strategy:** six tiers landing in independent PRs, ordered so each tier ships value on its own.

---

## 0. Glossary

| Term | Meaning |
|---|---|
| **Wire client** | A Swift type that speaks adb's binary TCP protocol directly to `127.0.0.1:5037`, replacing `Process()`+`adb` CLI calls. |
| **Sync channel** | An adb wire-protocol `sync:` stream — supports `LIST`, `STAT`, `RECV`, `SEND` against one file. |
| **Materialized** | A File Provider item whose contents currently exist on local disk (so Finder doesn't need to re-fetch). |
| **App-group transfer area** | `~/Library/Group Containers/group.com.merkost.freedroid/Transfers/` — writable from host, appex, and bridge. |
| **Content key** | The cache key derived from `(deviceID, path, mtime-or-fallback, sizeBytes)`. Stable per content version. |

---

## 1. Tier 0 — One-shot transfers (this PR)

**Effort:** ~1 day · **Speedup:** ~100× on big files · **Risk:** low

### 1.1 Public API addition

Extend `Sources/FreeDroidDomain/Transport/Transport.swift`:

```swift
public protocol Transport: Actor {
    // existing …
    func fetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64
    func upload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64
}

public protocol TransferProgressSink: Sendable {
    func report(bytesTransferred: Int64, totalBytes: Int64?)
}
```

Default-implementation rule: `fetch` and `upload` fall back to the old chunked path when not overridden, so we can land the protocol additions even before each transport is rewritten.

### 1.2 IPC additions

`Sources/FreeDroidIPC/IPCRequest.swift`:

```swift
public enum IPCRequest: Codable, Sendable {
    // existing …
    case fetchToFile(deviceID: DeviceID, path: RemotePath, destination: String)
    case uploadFromFile(deviceID: DeviceID, source: String, path: RemotePath)
}
```

`IPCResponse` already has `.data` and `.failure`; add nothing — successful transfer returns `.empty`.

The `destination` and `source` strings are absolute paths in the app-group transfer area (see §1.5). Both sides write/read directly.

### 1.3 Bridge handler

`FreeDroidBridge/BridgeHandler.swift::execute(_:)` adds:

```swift
case let .fetchToFile(deviceID, path, destination):
    try await sessions.session(for: deviceID.raw)
        .fetch(path, into: URL(fileURLWithPath: destination), progress: nil)
    return .empty
case let .uploadFromFile(deviceID, source, path):
    try await sessions.session(for: deviceID.raw)
        .upload(from: URL(fileURLWithPath: source), to: path, progress: nil)
    return .empty
```

Progress reporting via IPC is **not** in Tier 0 — see Tier 3 for streaming progress over an XPC observer interface. For now, the appex measures progress by polling file size at the destination on a 250ms timer; good enough for the visual.

### 1.4 ADBSession implementation

`Sources/FreeDroidADB/ADBSession.swift`:

```swift
public func fetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64 {
    let runner = await server.runner(for: serial)
    _ = try await runner.run(.pull(serial: serial, remote: path.raw, local: destination.path), timeout: .seconds(600))
    let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
    let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    progress?.report(bytesTransferred: size, totalBytes: size)
    return size
}

public func upload(from source: URL, to path: RemotePath, progress: TransferProgressSink?) async throws -> Int64 {
    let runner = await server.runner(for: serial)
    let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
    _ = try await runner.run(.push(serial: serial, local: source.path, remote: path.raw), timeout: .seconds(600))
    progress?.report(bytesTransferred: size, totalBytes: size)
    return size
}
```

One subprocess, one stream, one disk pass. The old `read/write` chunked methods stay for tiny operations (preview thumbnails, etc.) but no longer power large transfers.

### 1.5 App-group transfer area

`Sources/FreeDroidIPC/IPCEndpoint.swift`:

```swift
public static func transferDirectory() -> URL {
    let url = groupContainerURL()?.appendingPathComponent("Transfers", isDirectory: true)
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

public static func newTransferURL(extension ext: String) -> URL {
    transferDirectory().appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
}
```

Both the appex (sandboxed, sees the container via `containerURL(forSecurityApplicationGroupIdentifier:)`) and the bridge (no sandbox, sees the same dir via `NSHomeDirectory()/Library/Group Containers/…`) point at the same physical files.

### 1.6 File Provider rewrite

`FreeDroidProvider/FreeDroidProviderExtension.swift::fetchContents`:

```swift
let entry = try await transport.stat(path)
let tempURL = IPCEndpoint.newTransferURL(extension: (entry.name as NSString).pathExtension)
progress.totalUnitCount = entry.sizeBytes ?? -1
let pollTask = startProgressPoller(at: tempURL, into: progress, total: entry.sizeBytes)
defer { pollTask.cancel() }
try await transport.fetch(path, into: tempURL, progress: nil)
let finalEntry = try await transport.stat(path)
completionHandler(tempURL, ProviderItem(entry: finalEntry, parent: path.parent ?? .root), nil)
```

`startProgressPoller` is a 250 ms `Task` that reads `attributesOfItem(atPath:).size` and updates `progress.completedUnitCount`. Cancelled on success or error.

### 1.7 TransferEngine rewrite

`Sources/FreeDroidData/Transfer/TransferEngine.swift::pull` collapses from the chunked loop into:

```swift
public func pull(_ path: RemotePath, to localURL: URL) async throws -> Int64 {
    try Task.checkCancellation()
    let size = try await transport.fetch(path, into: localURL, progress: progressSink)
    try Task.checkCancellation()
    return size
}
```

Same change for any matching `push`.

### 1.8 MTP chunked write fix

`Sources/FreeDroidMTP/MTPSession.swift::write` currently throws on `data.count > maxWriteChunkBytes`. Replace with `LIBMTP_Send_File_From_Handler` so libmtp owns the streaming and we just provide a read callback. Effort: ~50 LOC in the C-shim + Swift wrapper. Unblocks all MTP uploads >256 KB.

### 1.9 Tests

- `Tests/FreeDroidADBTests/ADBSessionTransferTests.swift` — stub runner; assert `fetch` invokes **exactly one** `.pull` command and writes to the requested URL.
- `Tests/FreeDroidDataTests/TransferEnginePerfTests.swift` — assert single transport.fetch call per file.
- `Tests/FreeDroidMTPTests/MTPChunkedWriteTests.swift` — large-data write doesn't throw on the chunk-size guard.

### 1.10 Acceptance

- `swift test` green.
- Manual: drag a 100 MB file from `~/Library/CloudStorage/FreeDroid-<device>/sdcard/DCIM/Camera/` to the Desktop. Should complete in ~5–10 s on USB-3 ADB vs the current ~minute+.
- Manual: drag a 5 MB photo *to* the phone. Completes in ~1 s; the in-app browser reflects it on next refresh.

---

## 2. Tier 1 — Local content cache

**Effort:** 2 days · **Speedup:** instant on cache hit · **Risk:** medium

### 2.1 Cache layout

```
~/Library/Caches/FreeDroid/Content/
  └── <deviceID-sanitized>/
      └── <sha256-of-content-key>/
          ├── meta.json    # {key, fetchedAt, size, version}
          └── <filename>   # the actual file payload
```

`Content key = "<deviceID>|<path.raw>|<mtime-or-0>|<size>"`. SHA-256 over UTF-8.

Cache dir is **outside** `NSTemporaryDirectory()` so macOS doesn't purge mid-transfer under disk pressure.

### 2.2 New module: `Sources/FreeDroidContentCache/`

Single-file actor:

```swift
public actor ContentCache {
    public init(rootURL: URL, capacityBytes: Int64 = 10 * 1024 * 1024 * 1024)
    public func lookup(key: ContentKey) -> URL?
    public func store(_ source: URL, key: ContentKey, size: Int64) async throws -> URL
    public func evict(matching: (ContentKey) -> Bool)
    public func totalSizeBytes() -> Int64
}
```

LRU eviction keyed off `meta.json::fetchedAt`. Async-safe via the actor.

### 2.3 Provider integration

`fetchContents` checks `cache.lookup(key:)` before issuing `transport.fetch`. On hit: hardlink the cached file to a fresh URL (Finder requires the URL it gets back to be "unique enough"; hardlinks make this O(1)).

After `fetch`: store the temp file into the cache via `cache.store(...)`.

### 2.4 Invalidation

- Implicit: content key includes mtime+size; modifying the file on the phone changes the key, old cache entry orphaned (cleaned by LRU eventually).
- Explicit: `cache.evict(matching:)` called from `modifyItem`, `deleteItem` for the affected path.
- User-initiated: Settings → "Clear cache" button (`evict` all).

### 2.5 Settings UI

`FreeDroid/Settings/SettingsView.swift` adds a Cache section:
- "Cache size on disk: 4.2 GB of 10 GB" (uses `cache.totalSizeBytes`)
- Slider 1 GB – 50 GB
- "Clear cache" button

### 2.6 Tests

- Cache hit on same `(path, mtime, size)`.
- Cache miss on mtime change.
- LRU eviction at capacity.
- Concurrent `lookup` + `store` calls don't corrupt the cache.

---

## 3. Tier 2 — Range requests *(skipped; absorbed into Tier 3)*

Random-access mid-file reads (PDF tail, MOV seek) become cheap once Tier 3's wire client lands. Don't ship a separate intermediate.

---

## 4. Tier 3 — Native ADB wire-protocol client

**Effort:** 3–4 days · **Speedup:** 110 ms → 5 ms per op · **Risk:** medium-high

### 4.1 Protocol references

- [`SERVICES.TXT`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/SERVICES.TXT) — host-level commands (`host:devices`, `host:transport:<serial>`, `shell:`, `sync:`).
- [`SYNC.TXT`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/SYNC.TXT) — `LIST`, `LIST_V2`, `STAT`, `STAT_V2`, `SEND`, `RECV`, `DONE`, `OKAY`, `FAIL` packet shapes.

The on-the-wire framing for host messages: `<4-hex-length><ASCII-command>`. The server replies `OKAY` or `FAIL`. Most commands then upgrade the socket to a binary transport stream.

### 4.2 New submodule `Sources/FreeDroidADB/Wire/`

```
ADBWireConnection.swift      — opens TCP to 127.0.0.1:5037, framing helpers
ADBHostClient.swift          — host:devices, host:transport-id, version
ADBSyncClient.swift          — LIST_V2, STAT_V2, SEND, RECV
ADBShellClient.swift         — shell:command channel (for mkdir/rm/mv)
ADBWireError.swift           — typed errors mapped to TransportError
ADBProtocolMessage.swift     — packet structs (4-byte ID + 4-byte length + payload)
```

`ADBWireConnection` owns one `NWConnection` (Network.framework) on `127.0.0.1:5037`. Reconnects on drop. One connection multiplexed across many sync channels (each channel is a fresh TCP-style stream after a host:transport-id command).

### 4.3 Sync RECV implementation

Pseudocode:

```swift
func recv(remotePath: String, to local: URL, progress: TransferProgressSink?) async throws -> Int64 {
    try await sync.send(command: "RECV", argument: remotePath)
    let file = try FileHandle(forWritingTo: local)
    defer { try? file.close() }
    var total: Int64 = 0
    while true {
        let header = try await sync.readBytes(8) // 4-byte ID + 4-byte length
        let id = header.prefix(4)
        let length = header.suffix(4).readU32LE()
        switch id {
        case "DATA":
            let chunk = try await sync.readBytes(Int(length))
            try file.write(contentsOf: chunk)
            total += Int64(length)
            progress?.report(bytesTransferred: total, totalBytes: nil)
        case "DONE":
            return total
        case "FAIL":
            let msg = try await sync.readString(Int(length))
            throw ADBWireError.syncFailed(msg)
        default:
            throw ADBWireError.unexpectedTag(id)
        }
    }
}
```

`SEND` mirror-image for uploads.

### 4.4 LIST replacement

`ADBSession.list` no longer parses `ls -alL` shell output. Instead:

```swift
let entries = try await syncClient.listv2(remotePath: path.raw)
// each entry: name, mode, size, mtime, … as binary structs
```

Faster, less fragile, and exposes proper mtime (no more locale-dependent date parsing).

### 4.5 Migration strategy

`LiveADBRunner` stays for `start-server`, `kill-server`, `pair`, `connect`, `disconnect`. Everything else moves to the wire client behind a feature flag (`UserDefaults` key `freedroid.useWireClient`) during development; flip to default-on once the test matrix is green.

### 4.6 Cancellation

`ADBWireConnection` exposes a `cancel()` that closes the socket. `Task.cancellation` propagates by checking before each socket read/write.

### 4.7 Tests

- `Tests/FreeDroidADBWireTests/` — bring up a local stub adb-server (small Swift NIO listener that replies to canned commands); end-to-end RECV/SEND/LIST against it.
- Roundtrip tests: write 100 MB random data via SEND, read it back via RECV, assert identical.

---

## 5. Tier 4 — Parallel transfers

**Effort:** 1 day on top of Tier 3 · **Risk:** low

`TransferEngine` gains a per-device `TaskGroup` with bounded concurrency:

```swift
public init(maxParallelPerDevice: Int = 3)
```

Each child task opens its own sync channel via the shared `ADBWireConnection`. Progress is aggregated per-job via a `Progress` child-count.

Settings UI: "Parallel transfers per device: 1 / 3 / 5 / 8" picker.

---

## 6. Tier 5 — zstd compression

**Effort:** 1 day · **Risk:** low

When the server reports `feature:zstd_decompress` and `feature:zstd_compress` in `host:features`, append `--zstd` to `pull/push` invocations (or set the zstd flag in the wire-client header). Android 13+ phones speed up ~2–3× on text/source/log files.

Silent fallback when not supported.

---

## 7. Tier 6 — MTP transport rewrite

**Effort:** 3 days · **Risk:** medium

### 7.1 Current state

`MTPSession.read/write` currently throws on large data and the listing path eagerly slurps the whole tree.

### 7.2 New shape

```swift
func fetch(_ path: RemotePath, into destination: URL, progress: TransferProgressSink?) async throws -> Int64 {
    let storageID = try resolveStorage(for: path)
    let objectID = try resolveObject(at: path)
    try await withCheckedThrowingContinuation { cont in
        LIBMTP_Get_File_To_Handler(
            device,
            objectID,
            { buffer, size, callbackContext in
                let context = Unmanaged<MTPFetchContext>.fromOpaque(callbackContext!).takeUnretainedValue()
                context.fileHandle.write(Data(bytes: buffer, count: Int(size)))
                context.bytesWritten += Int64(size)
                context.progress?.report(bytesTransferred: context.bytesWritten, totalBytes: context.expectedSize)
                return Int32(size) // tell libmtp how many bytes we accepted
            },
            opaquePointer,
            { sent, total, callbackContext in
                // optional progress
                return 0
            },
            opaquePointer
        )
    }
    return totalBytes
}
```

Mirror-image for `LIBMTP_Send_File_From_Handler`.

`CLibmtp` shim grows a few helper functions for the callbacks since `@convention(c)` closures can't capture context easily.

### 7.3 Listing

Replace the current "fetch everything then filter" with `LIBMTP_Get_Files_And_Folders(device, storageID, parentObjectID)` — returns only the immediate children of a given parent, much faster.

### 7.4 Multi-storage

Sony / Sharp / some Hisense devices expose multiple `LIBMTP_devicestorage_t` (phone storage + SD card). Add a folder-picker dropdown at the gallery / browser root that lets the user choose the storage.

---

## 8. Cross-tier touchpoints

### 8.1 Progress reporting (Tier 0 → Tier 3 → Tier 6)

Tier 0 polls file size on disk. Tier 3 emits `DATA` packets with real byte counts. Tier 6 uses libmtp's progress callback. All three feed into the same `TransferProgressSink` protocol so the UI (`TransfersViewModel`, File Provider `Progress`) doesn't care about the source.

### 8.2 NSFileProviderItem updates (any Tier)

`itemVersion.contentVersion` becomes the **content key** SHA. Cache hits then deduplicate on the FP layer too — Finder won't even ask for `fetchContents` if it already has the right contentVersion.

### 8.3 Cancellation propagation

- Tier 0: `Task.cancel()` → `Process.terminate()` → `adb pull` aborts → temp file deleted by `defer`.
- Tier 3: `Task.cancel()` → `NWConnection.cancel()` → socket closes → server aborts the sync channel.
- Tier 6: `Task.cancel()` → `LIBMTP_Cancel_Operation(device)` (libmtp 1.1.21+ supports this).

### 8.4 Sandbox / entitlements

No new entitlements needed across all tiers. The bridge already has `network.client` (Tier 3), the appex already has `application-groups` (Tier 0 transfer dir), libmtp is bundled (Tier 6).

---

## 9. Release sequencing

| Tier | PR | When | Headline number |
|---|---|---|---|
| 0 | this PR | today | 1 GB pull: 3 min → 12 s |
| 1 | next PR | this week | repeat Quick Look: 12 s → 0 ms |
| 3 | following PR | this/next week | per-op latency 110 ms → 5 ms |
| 4 | folded into 3 | same | multi-file 3× |
| 5 | tiny PR after 3 | when ready | text-file 2× |
| 6 | independent track | parallel | MTP works for big files at all |

Tier 0 alone gets us out of "user is waiting." Everything above 0 is polish + parity + bragging-rights speed.

---

## 10. Out of scope (explicit)

- macFUSE backend.
- iOS / iPadOS counterpart.
- Cloud sync.
- Background transfers when the app is closed.
- Selective sync rules.
- Bandwidth throttling.

Any of these can be future tiers.

---

*Spec author: Claude · 2026-05-12 · Companion to `2026-05-12-transfer-performance.md`*
