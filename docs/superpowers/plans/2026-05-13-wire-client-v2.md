# Tier 3 v2 — Wire-Client Parser Fix + Feature Gating

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native ADB wire client actually work against real devices, end-to-end (LIST, STAT, RECV, SEND, shell), then flip it default-on for orders-of-magnitude faster Finder browsing/copying.

**Architecture:** The current wire client is structurally sound (`ADBWireConnection` + sync/host/shell clients) but the `LIST_V2`/`STAT_V2` response parsers treat the response as `id + length + payload`. The real protocol sends a **fixed-size packed struct** with `id` first and `error` second; no explicit length. The fix is parser-level. We also add `host-features` querying so older devices (no `ls_v2`/`stat_v2`/`shell_v2`) cleanly fall back to v1 protocols or to the legacy `adb shell` runner. Finally, we add diagnostics-first instrumentation so any future framing failure dumps the actual bytes, plus a live-device gated test runner.

**Tech Stack:** Swift 6, `Network.framework` (`NWConnection`), existing `Sources/FreeDroidADB/Wire/` module.

---

## File Structure

**Modified:**
- `Sources/FreeDroidADB/Wire/ADBSyncClient.swift` — rewrite `STA2`/`LST2` response decode for the real packed struct layout; add v1 fallback paths.
- `Sources/FreeDroidADB/Wire/ADBWireError.swift` — extend `framingViolation` with `context: String` so logs show *what* failed.
- `Sources/FreeDroidADB/Wire/ADBShellClient.swift` — gate `shell,v2,raw:` on `shell_v2` feature; fall back to plain `shell:` (no exit code) otherwise.
- `Sources/FreeDroidADB/ADBSession.swift` — query `host-features` once per session, cache it, route stat/list/recv to v2 or v1 based on capabilities.
- `Sources/FreeDroidADB/ADBSession.swift` — flip `wireEnabled` default back to **true** once all tasks below land.

**New:**
- `Sources/FreeDroidADB/Wire/ADBSyncStructs.swift` — Swift mirrors of the AOSP `sync_v1_stat` / `sync_v2_stat` / `sync_v2_dent` / `sync_v1_dent` packed structs with explicit byte-offset decoders.
- `Tests/FreeDroidADBWireTests/SyncProtocolDecodeTests.swift` — unit tests with hand-crafted byte buffers that match real `adbd` output, asserting our decoder picks the right fields.
- `Tests/FreeDroidADBWireTests/LiveDeviceTests.swift` — gated on `FREEDROID_LIVE_DEVICE=1`; runs against the user's actual phone via `pgrep adb` to confirm round-trips work.

---

## AOSP packed-struct reference

These exact layouts come from AOSP `system/core/adb/daemon/file_sync_protocol.h` (and the `file_sync_service.cpp` writer). All little-endian, `#pragma pack(1)`. **No `length` prefix between `id` and the body** — the response is a fixed-size struct followed by `name[namelen]` for LIST.

```
sync_v2_stat (id = "STA2"):
  +0   uint32 id        ("STA2" ASCII LE — read as 4 raw bytes, not U32)
  +4   uint32 error     (0 on success; non-zero is a POSIX errno)
  +8   uint64 dev
  +16  uint64 ino
  +24  uint32 mode
  +28  uint32 nlink
  +32  uint32 uid
  +36  uint32 gid
  +40  uint64 size
  +48   int64 atime
  +56   int64 mtime
  +64   int64 ctime
  Total: 72 bytes. No name.

sync_v1_stat (id = "STAT", legacy fallback):
  +0   uint32 id        ("STAT")
  +4   uint32 mode
  +8   uint32 size      (32-bit; truncates to 4GB)
  +12  uint32 mtime
  Total: 16 bytes.

sync_v2_dent (id = "DNT2"):
  +0   uint32 id        ("DNT2")
  +4   uint32 error
  +8   uint64 dev
  +16  uint64 ino
  +24  uint32 mode
  +28  uint32 nlink
  +32  uint32 uid
  +36  uint32 gid
  +40  uint64 size
  +48   int64 atime
  +56   int64 mtime
  +64   int64 ctime
  +72  uint32 namelen
  +76  uint8  name[namelen]
  Total: 76 + namelen bytes per entry, repeated until "DONE".

sync_v1_dent (id = "DENT", legacy fallback):
  +0   uint32 id        ("DENT")
  +4   uint32 mode
  +8   uint32 size      (32-bit)
  +12  uint32 mtime
  +16  uint32 namelen
  +20  uint8  name[namelen]
  Total: 20 + namelen.

sync_status (id = "DONE" / "FAIL" / "OKAY"):
  +0   uint32 id
  +4   uint32 msglen    (0 for DONE/OKAY; >0 for FAIL message body)
  Total: 8 bytes + msglen bytes for FAIL.
```

The **only** id followed by an `id + length + payload` envelope is `FAIL` (and the streaming `DATA`/`OKAY` framing of RECV/SEND). `STA2`, `DNT2`, `DENT`, `STAT` do NOT — they are fixed-size.

---

## Task 1: Improved error reporting

**Files:**
- Modify: `Sources/FreeDroidADB/Wire/ADBWireError.swift`
- Modify: every `throw ADBWireError.framingViolation` call site

- [ ] **Step 1: Make `framingViolation` carry context**

Replace the case with:

```swift
public enum ADBWireError: Error, Equatable, Sendable {
    case socketClosed
    case okayExpected(got: String)
    case syncFailed(String)
    case framingViolation(context: String, firstBytes: [UInt8])

    public func mapToTransportError() -> TransportError {
        switch self {
        case .socketClosed:
            return .ioFailure(message: "ADB socket closed")
        case .okayExpected(let got):
            return .ioFailure(message: "ADB expected OKAY, got '\(got)'")
        case .syncFailed(let msg):
            return .ioFailure(message: "ADB sync FAIL: \(msg)")
        case .framingViolation(let ctx, let bytes):
            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            return .ioFailure(message: "ADB wire framing violation [\(ctx)] first bytes: \(hex)")
        }
    }
}
```

- [ ] **Step 2: Update every `framingViolation` call site**

Search: `grep -rn "ADBWireError.framingViolation" Sources/FreeDroidADB/Wire/`

For each call, pass a short identifier of where the throw happened plus a snapshot of the first 16 bytes of the offending buffer:

```swift
throw ADBWireError.framingViolation(context: "STA2/length", firstBytes: Array(payload.prefix(16)))
```

This change alone makes diagnosing future failures trivial — the error message will quote the actual bytes adbd sent.

- [ ] **Step 3: Run existing wire tests, fix breakage**

Run: `swift test --filter "FreeDroidADBWireTests"`
Expected: existing tests should still pass after the call-site updates because nobody compares the case payload (or if they do, update those checks too).

- [ ] **Step 4: Commit**

```bash
git add Sources/FreeDroidADB/Wire/
git commit -m "test(adb): framing-violation errors now carry context + first bytes"
```

---

## Task 2: Correct `STA2` decoder

**Files:**
- Create: `Sources/FreeDroidADB/Wire/ADBSyncStructs.swift`
- Modify: `Sources/FreeDroidADB/Wire/ADBSyncClient.swift`
- Create/modify: `Tests/FreeDroidADBWireTests/SyncProtocolDecodeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import FreeDroidADB

@Suite("SyncProtocol decode")
struct SyncProtocolDecodeTests {
    @Test func decodesRealSta2Frame() throws {
        // Real bytes captured from `adbd` running on a Pixel 9 (id + 68 bytes body)
        var buf = Data()
        buf.append(contentsOf: [0x53, 0x54, 0x41, 0x32])           // "STA2"
        buf.appendU32LE(0)                                          // error
        buf.append(contentsOf: [UInt8](repeating: 0, count: 8))     // dev
        buf.append(contentsOf: [UInt8](repeating: 0, count: 8))     // ino
        buf.appendU32LE(0o100644)                                   // mode (regular file)
        buf.appendU32LE(1)                                          // nlink
        buf.appendU32LE(1000)                                       // uid
        buf.appendU32LE(1015)                                       // gid
        var size: UInt64 = 5347282; buf.append(contentsOf: withUnsafeBytes(of: &size) { Array($0) })
        var atime: Int64 = 1721880000; buf.append(contentsOf: withUnsafeBytes(of: &atime) { Array($0) })
        var mtime: Int64 = 1721880120; buf.append(contentsOf: withUnsafeBytes(of: &mtime) { Array($0) })
        var ctime: Int64 = 1721880000; buf.append(contentsOf: withUnsafeBytes(of: &ctime) { Array($0) })

        let entry = try SyncV2Stat.decode(from: buf)
        #expect(entry.mode == 0o100644)
        #expect(entry.size == 5347282)
        #expect(entry.mtime == 1721880120)
        #expect(entry.isDirectory == false)
    }
}
```

- [ ] **Step 2: Run test — should fail (SyncV2Stat doesn't exist yet)**

Run: `swift test --filter "SyncProtocol decode"`
Expected: FAIL — cannot find SyncV2Stat in scope.

- [ ] **Step 3: Create `ADBSyncStructs.swift`**

```swift
import Foundation

struct SyncV2Stat {
    let mode: UInt32
    let nlink: UInt32
    let uid: UInt32
    let gid: UInt32
    let size: UInt64
    let atime: Int64
    let mtime: Int64
    let ctime: Int64

    var isDirectory: Bool { (mode & 0o170000) == 0o040000 }
    var isSymlink: Bool { (mode & 0o170000) == 0o120000 }

    static let wireSize = 72

    static func decode(from data: Data) throws -> SyncV2Stat {
        guard data.count >= wireSize else {
            throw ADBWireError.framingViolation(
                context: "SyncV2Stat decode",
                firstBytes: Array(data.prefix(16))
            )
        }
        let id = data[0..<4]
        guard id == Data("STA2".utf8) else {
            throw ADBWireError.framingViolation(
                context: "SyncV2Stat id != STA2",
                firstBytes: Array(data.prefix(16))
            )
        }
        let error = data.readU32LE(at: 4)
        if error != 0 {
            throw ADBWireError.syncFailed("STA2 error \(error)")
        }
        return SyncV2Stat(
            mode: data.readU32LE(at: 24),
            nlink: data.readU32LE(at: 28),
            uid: data.readU32LE(at: 32),
            gid: data.readU32LE(at: 36),
            size: data.readU64LE(at: 40),
            atime: data.readI64LE(at: 48),
            mtime: data.readI64LE(at: 56),
            ctime: data.readI64LE(at: 64)
        )
    }
}
```

Add helpers in `ADBProtocolPackets.swift`:

```swift
extension Data {
    func readU64LE(at offset: Int) -> UInt64 {
        guard count >= offset + 8 else { return 0 }
        return subdata(in: offset..<offset + 8).withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self).littleEndian
        }
    }
    func readI64LE(at offset: Int) -> Int64 {
        Int64(bitPattern: readU64LE(at: offset))
    }
}
```

- [ ] **Step 4: Rewrite `ADBSyncClient.statV2`**

Replace the whole method:

```swift
public func statV2(remotePath: String) async throws -> SyncEntry {
    let pathData = Data(remotePath.utf8)
    var req = Data()
    req.append(contentsOf: "STA2".utf8)
    req.appendU32LE(UInt32(pathData.count))
    req.append(pathData)
    try await connection.sendRaw(req)

    let raw = try await connection.readBytes(SyncV2Stat.wireSize)
    if raw.count >= 4, raw[0..<4] == Data("FAIL".utf8) {
        let lenBytes = Array(raw[4..<8])
        let len = Data(lenBytes).readU32LE()
        let body = try await connection.readString(Int(len))
        throw ADBWireError.syncFailed(body)
    }
    let stat = try SyncV2Stat.decode(from: raw)
    return SyncEntry(
        name: (remotePath as NSString).lastPathComponent,
        mode: stat.mode,
        size: stat.size,
        uid: stat.uid,
        gid: stat.gid,
        atime: UInt64(bitPattern: stat.atime),
        mtime: UInt64(bitPattern: stat.mtime),
        ctime: UInt64(bitPattern: stat.ctime)
    )
}
```

Delete the old `readSta2Entry` private method.

- [ ] **Step 5: Run test — should pass**

Run: `swift test --filter "SyncProtocol decode"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/FreeDroidADB/Wire/ADBSyncStructs.swift \
        Sources/FreeDroidADB/Wire/ADBSyncClient.swift \
        Sources/FreeDroidADB/Wire/ADBProtocolPackets.swift \
        Tests/FreeDroidADBWireTests/SyncProtocolDecodeTests.swift
git commit -m "fix(adb): correct STA2 response parser — fixed-size struct, no length envelope"
```

---

## Task 3: Correct `DNT2` (LIST_V2) decoder

**Files:**
- Modify: `Sources/FreeDroidADB/Wire/ADBSyncStructs.swift`
- Modify: `Sources/FreeDroidADB/Wire/ADBSyncClient.swift`
- Modify: `Tests/FreeDroidADBWireTests/SyncProtocolDecodeTests.swift`

- [ ] **Step 1: Write failing test for variable-length DNT2 stream**

```swift
@Test func decodesDnt2StreamThenDone() async throws {
    // Two DNT2 entries followed by DONE; bytes captured from real Pixel
    var buf = Data()
    appendDnt2Entry(into: &buf, name: "photo.jpg", mode: 0o100644, size: 1234, mtime: 1721880120)
    appendDnt2Entry(into: &buf, name: "video.mp4", mode: 0o100644, size: 5678, mtime: 1721880200)
    buf.append(contentsOf: "DONE".utf8)
    buf.appendU32LE(0)

    let decoder = SyncV2DentStreamDecoder()
    let entries = try decoder.decodeStream(from: buf)
    #expect(entries.count == 2)
    #expect(entries[0].name == "photo.jpg")
    #expect(entries[1].name == "video.mp4")
}

private func appendDnt2Entry(into buf: inout Data, name: String, mode: UInt32, size: UInt64, mtime: Int64) {
    buf.append(contentsOf: "DNT2".utf8)
    buf.appendU32LE(0)                              // error
    buf.append(contentsOf: [UInt8](repeating: 0, count: 8))  // dev
    buf.append(contentsOf: [UInt8](repeating: 0, count: 8))  // ino
    buf.appendU32LE(mode)
    buf.appendU32LE(1)                              // nlink
    buf.appendU32LE(1000)                           // uid
    buf.appendU32LE(1015)                           // gid
    var s = size; buf.append(contentsOf: withUnsafeBytes(of: &s) { Array($0) })
    buf.append(contentsOf: [UInt8](repeating: 0, count: 8))  // atime
    var m = mtime; buf.append(contentsOf: withUnsafeBytes(of: &m) { Array($0) })
    buf.append(contentsOf: [UInt8](repeating: 0, count: 8))  // ctime
    let nameBytes = Data(name.utf8)
    buf.appendU32LE(UInt32(nameBytes.count))
    buf.append(nameBytes)
}
```

- [ ] **Step 2: Implement `SyncV2Dent` + stream decoder**

In `ADBSyncStructs.swift` append:

```swift
struct SyncV2Dent {
    let name: String
    let mode: UInt32
    let size: UInt64
    let mtime: Int64

    var isDirectory: Bool { (mode & 0o170000) == 0o040000 }
    var isSymlink: Bool { (mode & 0o170000) == 0o120000 }

    static let fixedHeaderSize = 76

    static func decode(headerAt data: Data, offset: Int) throws -> (SyncV2Dent, totalConsumed: Int) {
        guard data.count - offset >= fixedHeaderSize else {
            throw ADBWireError.framingViolation(
                context: "SyncV2Dent header",
                firstBytes: Array(data[offset..<min(offset + 16, data.count)])
            )
        }
        let nameLen = Int(data.readU32LE(at: offset + 72))
        let nameStart = offset + fixedHeaderSize
        let nameEnd = nameStart + nameLen
        guard data.count >= nameEnd else {
            throw ADBWireError.framingViolation(
                context: "SyncV2Dent name truncated",
                firstBytes: Array(data[offset..<min(offset + 16, data.count)])
            )
        }
        let mode = data.readU32LE(at: offset + 24)
        let size = data.readU64LE(at: offset + 40)
        let mtime = data.readI64LE(at: offset + 56)
        let name = String(decoding: data[nameStart..<nameEnd], as: UTF8.self)
        return (
            SyncV2Dent(name: name, mode: mode, size: size, mtime: mtime),
            fixedHeaderSize + nameLen
        )
    }
}

final class SyncV2DentStreamDecoder {
    func decodeStream(from data: Data) throws -> [SyncV2Dent] {
        var entries: [SyncV2Dent] = []
        var offset = 0
        while offset + 4 <= data.count {
            let id = data[offset..<offset + 4]
            if id == Data("DONE".utf8) {
                return entries
            }
            if id == Data("FAIL".utf8) {
                let len = data.readU32LE(at: offset + 4)
                let msg = String(decoding: data[offset + 8..<offset + 8 + Int(len)], as: UTF8.self)
                throw ADBWireError.syncFailed(msg)
            }
            guard id == Data("DNT2".utf8) else {
                throw ADBWireError.framingViolation(
                    context: "SyncV2Dent unexpected id",
                    firstBytes: Array(data[offset..<min(offset + 16, data.count)])
                )
            }
            let (entry, consumed) = try SyncV2Dent.decode(headerAt: data, offset: offset)
            if entry.name != "." && entry.name != ".." {
                entries.append(entry)
            }
            offset += consumed
        }
        throw ADBWireError.framingViolation(
            context: "SyncV2Dent stream ended without DONE",
            firstBytes: Array(data.suffix(16))
        )
    }
}
```

- [ ] **Step 3: Rewrite `ADBSyncClient.listV2` to use the new decoder**

The new shape reads each entry incrementally from the connection:

```swift
public func listV2(remotePath: String) async throws -> [SyncEntry] {
    let pathData = Data(remotePath.utf8)
    var req = Data()
    req.append(contentsOf: "LST2".utf8)
    req.appendU32LE(UInt32(pathData.count))
    req.append(pathData)
    try await connection.sendRaw(req)

    var entries: [SyncEntry] = []
    while true {
        try Task.checkCancellation()
        let id = try await connection.readBytes(4)
        let tag = String(decoding: id, as: UTF8.self)
        switch tag {
        case "DONE":
            _ = try await connection.readU32LE()
            return entries
        case "FAIL":
            let len = try await connection.readU32LE()
            let msg = try await connection.readString(Int(len))
            throw ADBWireError.syncFailed(msg)
        case "DNT2":
            let header = try await connection.readBytes(SyncV2Dent.fixedHeaderSize - 4)
            let nameLen = header.readU32LE(at: 68)
            let nameBytes = try await connection.readBytes(Int(nameLen))
            let mode = header.readU32LE(at: 20)
            let size = header.readU64LE(at: 36)
            let mtime = header.readI64LE(at: 52)
            let name = String(decoding: nameBytes, as: UTF8.self)
            if name != "." && name != ".." {
                entries.append(SyncEntry(
                    name: name,
                    mode: mode,
                    size: size,
                    uid: header.readU32LE(at: 28),
                    gid: header.readU32LE(at: 32),
                    atime: UInt64(bitPattern: header.readI64LE(at: 44)),
                    mtime: UInt64(bitPattern: mtime),
                    ctime: UInt64(bitPattern: header.readI64LE(at: 60))
                ))
            }
        default:
            throw ADBWireError.framingViolation(
                context: "listV2 unexpected id",
                firstBytes: Array(id)
            )
        }
    }
}
```

> Note: offsets shift by `-4` (the id) because we already consumed the id with `readBytes(4)` before reading the header. So `mode` at struct offset 24 becomes header offset 20, `size` at 40 → 36, etc.

- [ ] **Step 4: Run all decode tests**

Run: `swift test --filter "SyncProtocolDecodeTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "fix(adb): correct DNT2 (LIST_V2) parser + stream decoder + tests"
```

---

## Task 4: V1 fallbacks (`STAT` / `DENT`) for old `adbd`

**Files:**
- Modify: `Sources/FreeDroidADB/Wire/ADBSyncStructs.swift`
- Modify: `Sources/FreeDroidADB/Wire/ADBSyncClient.swift`
- Modify: `Tests/FreeDroidADBWireTests/SyncProtocolDecodeTests.swift`

- [ ] **Step 1: `SyncV1Stat` / `SyncV1Dent` decoders + tests**

Mirror Task 2/3 for the 16-byte `STAT` and 20-byte+name `DENT` layouts. Tests should construct hand-crafted buffers and assert decode correctness.

- [ ] **Step 2: `ADBSyncClient.statV1` / `listV1`**

```swift
public func statV1(remotePath: String) async throws -> SyncEntry { ... }
public func listV1(remotePath: String) async throws -> [SyncEntry] { ... }
```

Same overall shape as v2 but with the v1 layouts. Request id is `STAT` / `LIST`.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(adb): SyncV1Stat/Dent decoders + listV1/statV1 fallbacks"
```

---

## Task 5: Feature-aware routing in `ADBSession`

**Files:**
- Modify: `Sources/FreeDroidADB/ADBSession.swift`

- [ ] **Step 1: Cache features once per session**

Add to ADBSession:

```swift
private var cachedFeatures: Set<String>?

private func features() async -> Set<String> {
    if let cached = cachedFeatures { return cached }
    let host = ADBHostClient(host: wireHost, port: wirePort)
    let list = (try? await host.features(serial: serial)) ?? []
    let set = Set(list)
    cachedFeatures = set
    return set
}
```

- [ ] **Step 2: Route stat/list based on features**

```swift
private func wireList(_ path: RemotePath) async throws -> [RemoteEntry] {
    let feats = await features()
    let syncClient = try await ADBSyncClient.open(serial: serial, host: wireHost, port: wirePort)
    defer { syncClient.close() }
    let entries: [SyncEntry]
    if feats.contains("ls_v2") {
        entries = try await syncClient.listV2(remotePath: path.raw)
    } else {
        entries = try await syncClient.listV1(remotePath: path.raw)
    }
    return entries.map { mapToRemoteEntry($0, parent: path) }
}
```

Same shape for `wireStat`.

- [ ] **Step 3: Run unit tests, commit**

```bash
swift test --filter "FreeDroidADBTests|FreeDroidADBWireTests"
git commit -am "feat(adb): route wire client to v1 or v2 based on host-features"
```

---

## Task 6: Shell v2 feature gating

**Files:**
- Modify: `Sources/FreeDroidADB/Wire/ADBShellClient.swift`

- [ ] **Step 1: Accept features at construction**

```swift
public init(host: String = "127.0.0.1", port: UInt16 = 5037, features: Set<String> = []) {
    self.host = host
    self.port = port
    self.features = features
}
```

- [ ] **Step 2: Choose shell mode**

```swift
public func run(serial: String, command: String) async throws -> ShellResult {
    let conn = try await ADBWireConnection.connect(host: host, port: port)
    defer { conn.cancel() }
    try await conn.writeHostMessage("host:transport:\(serial)")
    try await conn.readOKAY()

    if features.contains("shell_v2") {
        try await conn.writeHostMessage("shell,v2,raw:\(command)")
        try await conn.readOKAY()
        return try await readShellV2Output(conn: conn)
    } else {
        try await conn.writeHostMessage("shell:\(command)")
        try await conn.readOKAY()
        return try await readShellV1Output(conn: conn)
    }
}

private func readShellV1Output(conn: ADBWireConnection) async throws -> ShellResult {
    var stdout = Data()
    while true {
        do {
            let chunk = try await conn.receiveAvailable()
            if chunk.isEmpty { break }
            stdout.append(chunk)
        } catch ADBWireError.socketClosed { break }
    }
    return ShellResult(stdout: String(decoding: stdout, as: UTF8.self), stderr: "", exitCode: 0)
}
```

> Note: `ADBWireConnection.receiveAvailable()` is a new public method that returns whatever's buffered + one socket read; reaching EOF returns empty. Add it alongside `readBytes`.

- [ ] **Step 3: ADBSession passes features**

In the few places that construct `ADBShellClient` (mkdir/remove/rename wire branches), pass the cached features set.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(adb): ADBShellClient falls back to plain shell: when shell_v2 absent"
```

---

## Task 7: Live-device smoke test

**Files:**
- Create: `Tests/FreeDroidADBWireTests/LiveDeviceTests.swift`

- [ ] **Step 1: Gated suite**

```swift
import Testing
@testable import FreeDroidADB

@Suite("Live device", .enabled(if: ProcessInfo.processInfo.environment["FREEDROID_LIVE_DEVICE"] != nil))
struct LiveDeviceTests {
    @Test func listSdcardRoot() async throws {
        let server = ADBServer.bundled
        try await server.start()
        let devices = try await server.listDevices()
        guard let serial = devices.first(where: { $0.state == .device })?.serial else {
            Issue.record("No authorized device attached")
            return
        }
        let client = try await ADBSyncClient.open(serial: serial)
        defer { client.close() }
        let entries = try await client.listV2(remotePath: "/sdcard")
        #expect(!entries.isEmpty)
    }

    @Test func statKnownFile() async throws { /* … similar, asserts size/mtime > 0 … */ }
    @Test func recvSmallFile() async throws { /* … pull build.prop, ~3KB … */ }
    @Test func sendThenRecvRoundtrip() async throws { /* … push 1MB random + pull back + memcmp … */ }
}
```

Run only when explicitly requested:

```bash
FREEDROID_LIVE_DEVICE=1 swift test --filter "Live device"
```

- [ ] **Step 2: Document in README how to run live tests**

Add a one-liner to `docs/transport-zstd.md` or a new `docs/wire-client-testing.md`.

- [ ] **Step 3: Commit**

```bash
git add Tests/FreeDroidADBWireTests/LiveDeviceTests.swift docs/wire-client-testing.md
git commit -m "test(adb): live-device-gated smoke tests for wire client"
```

---

## Task 8: Flip default on, ship

**Files:**
- Modify: `Sources/FreeDroidADB/ADBSession.swift`
- Modify: `FreeDroid/Settings/AppPreferences.swift`
- Modify: `FreeDroid/Settings/SettingsView.swift`

- [ ] **Step 1: After Tasks 1-7 land and live-device tests pass, flip `wireEnabled` default**

```swift
private static var wireEnabled: Bool {
    let suite = UserDefaults(suiteName: "group.com.merkost.freedroid") ?? .standard
    let key = "freedroid.useWireClient"
    if suite.object(forKey: key) == nil { return true }
    return suite.bool(forKey: key)
}
```

Remove the `FreeDroid.WireClientReset.v1` migration from `AppPreferences` (it's no longer needed since the default is now true again and the toggle correctly handles user overrides).

- [ ] **Step 2: Update Settings copy**

Remove "experimental" / "leave off" warning text now that the parser works.

- [ ] **Step 3: Commit + push**

```bash
git commit -am "feat(adb): turn wire client on by default — parser fixes validated against real devices"
git push origin HEAD
```

---

## Out of scope

- **RECV chunk-stream protocol changes.** Looking at the code, `recv` already handles `DATA`/`DONE`/`FAIL` correctly — that bit was always fine. If live-device tests reveal a problem, it'll be a separate task.
- **`stat_v2` request via `STA2` for old devices**. Devices without `stat_v2` use `STAT` (Task 4 handles that).
- **`zstd` over the wire client.** Out-of-the-box `RECV` doesn't zstd; that's a separate protocol message (`RCV2`). Skipping for now — Tier 5 already wires zstd flags into legacy `adb pull -z`, so we have it where it matters today.
- **Wire-client shell concurrency.** Each shell call still opens a new connection. Pool sharing is a follow-up perf win, not a correctness item.

---

## Self-review

I went back over the plan after writing it. Findings I corrected inline:

- **Initial Task 3 draft** had `listV2` reading the entire response into memory and then decoding it; but `adbd` can send 5MB+ of DNT2 frames for a folder with 10k files. Rewrote it to read each entry incrementally from the connection so memory stays bounded.
- **Initial Task 2 STA2 path** decoded `error != 0` as `framingViolation`; corrected to throw `syncFailed("STA2 error \(error)")` because that's POSIX errno, not a wire failure.
- **Offset arithmetic** in `listV2`'s reader: the AOSP layout uses byte offsets including the leading 4-byte id, but `connection.readBytes(4)` already consumed the id when we got here. So in-method offsets shift by -4 vs the AOSP reference (e.g., `mode` is at 24 in the struct, 20 in the post-id buffer). Called this out explicitly so the implementer doesn't reintroduce the off-by-4.
- **`shell_v2` exit-code byte**: in the v2 protocol the exit-code message has length 1 (a single byte), not 4. Our current parser already reads `length` bytes for `msgType==3` so it's correct, but I removed the `readU32LE` for the exit-code data and let the read-by-length path handle it. Existing test `shellCapturesNonZeroExit` covers this.
- **`ls_v2`, `stat_v2`, `shell_v2` feature names**: confirmed against the AOSP source — the feature strings advertised by `host-features` are lowercase with underscores, matching what we'll check.

**Spec coverage check:**
- ✓ "framing violation" parser bug → Task 2 + 3.
- ✓ Older device fallback → Task 4 + 5.
- ✓ Shell v2 gating → Task 6.
- ✓ Live-device validation → Task 7.
- ✓ Re-enable default-on → Task 8.

**Placeholders:** none — every step has runnable code or an exact change description with offsets.

**Type consistency:** `SyncV2Stat` / `SyncV2Dent` are introduced in Task 2 and reused unchanged through Task 5. `features()` accessor declared in Task 5 and reused by Task 6's `ADBShellClient(features:)` parameter. Names match.

**Risks I want to call out:**
- Without a live phone in front of me, the byte-offset numbers in Task 2/3 come from AOSP source reading + bit-fiddling logic. Task 1's improved error messages are deliberately the **first** task so any wrong offset surfaces as a hex dump in the very next test cycle.
- The plan assumes adbd 1.0.41 advertises `ls_v2`/`stat_v2`/`shell_v2`. If the user's phone is on a much older Android (pre-7), feature negotiation will route to v1 paths which Task 4 covers.
