# Transfer Performance — Analysis & Plan

**Date:** 2026-05-12
**Status:** Draft, not implemented
**Problem reported:** "macDroid makes it faster to transfer files — I'm waiting a lot here."

---

## TL;DR

Our current transfer code has an **O(file_size²)** read pattern and a **per-call adb subprocess spawn** that combine to torch performance on anything larger than a few megabytes. A 1 GB file takes roughly **1024 full `adb pull` invocations** under the current `fetchContents` loop, which means the phone re-streams the entire file ~1000 times over USB while macOS writes 1 GB to disk in a slicing dance.

Fixing the worst offender is **a one-day change** with a ~100× speedup for big files. Fixing all of it cleanly (native ADB sync protocol client, streaming reads, parallel transfers, MTP rewrite, compression) is **a one-week project** that brings FreeDroid roughly to macDroid parity on cold transfers and potentially ahead on cached re-fetches.

---

## 1. Where the time goes today

### Path A — File Provider `fetchContents`

`FreeDroidProvider/FreeDroidProviderExtension.swift` (the Finder copy path):

```swift
let chunkSize = 1 << 20                    // 1 MiB
var offset: Int64 = 0
while offset < total {
    let length = Int(min(Int64(chunkSize), total - offset))
    let chunk = try await transport.read(path, offset: offset, length: length)
    try handle.write(contentsOf: chunk)
    offset += Int64(chunk.count)
    progress.completedUnitCount = offset
}
```

`transport.read` is the bridge's IPC façade for `ADBSession.read`:

```swift
public func read(_ path: RemotePath, offset: Int64, length: Int) async throws -> Data {
    let temp = ADBFileSync.tempLocalPath()
    defer { try? FileManager.default.removeItem(at: temp) }
    let runner = await server.runner(for: serial)
    _ = try await runner.run(.pull(serial: serial, remote: path.raw, local: temp.path), timeout: .seconds(120))
    let data = try Data(contentsOf: temp)
    let start = Int(offset)
    let end = min(start + length, data.count)
    return data.subdata(in: start..<end)
}
```

**Every chunk request:**

1. Spawns a fresh `adb pull` subprocess  (~80 ms cold-start macOS overhead on Apple Silicon).
2. Pulls the **entire file** from the phone over USB.
3. Writes the entire file to a unique temp path under `/private/var/folders/…`.
4. `Data(contentsOf: temp)` slurps the whole file into RAM.
5. Slices the requested window.
6. Returns the slice; defers temp deletion.

For a **1 GB file at 1 MiB chunks**:

| Cost                           | Count | Total                                       |
|--------------------------------|-------|---------------------------------------------|
| `adb pull` subprocess spawn    | 1024  | ~80 s of pure overhead                      |
| Re-stream entire file over USB | 1024  | ~1 TB pretending to be 1 GB                 |
| Disk write of full file        | 1024  | ~1 TB SSD writes (wears out fast)           |
| RAM allocation of `Data`       | 1024  | 1 GB peak × 1024 = enormous cache pressure  |
| Useful bytes written           | 1     | 1 GB                                        |

Even cached in macOS unified buffer cache, that's ~1024× the necessary work.

### Path B — In-app transfer queue (`TransferEngine.pull`)

```swift
while offset < total {
    try Task.checkCancellation()
    // … reads chunks with the same `transport.read` …
}
```

Same loop, same `transport.read`, same pathology. Different code path, identical bug.

### Path C — Uploads (`ADBSession.write`)

```swift
public func write(_ path: RemotePath, data: Data, offset: Int64) async throws {
    guard offset == 0 else { throw .unsupported(reason: "…") }
    let temp = ADBFileSync.tempLocalPath()
    try data.write(to: temp)
    defer { try? FileManager.default.removeItem(at: temp) }
    _ = try await runner.run(.push(serial: serial, local: temp.path, remote: path.raw), timeout: .seconds(300))
}
```

Better than reads — accepts only `offset == 0` so it's effectively a one-shot push. The pathology is the **subprocess spawn per call** plus the staging-to-disk roundtrip when SwiftUI hands us a `Data` we could stream straight to the device. For a 5 GB video, this writes 5 GB to local disk *and* pushes 5 GB to the phone — 10 GB of I/O for a 5 GB transfer.

### Path D — MTP (`MTPSession.write`)

```swift
guard data.count <= quirks.maxWriteChunkBytes else {
    throw TransportError.unsupported(reason: "Chunked writes pending …")
}
```

MTP write is **functionally broken for large files** — refuses anything over the per-device chunk quirk (typically 256 KB – 4 MB). Users uploading big files via MTP just hit a wall.

### Subprocess overhead, measured

`time adb pull /sdcard/Download/empty.txt /tmp/x` on this Mac with adb 1.0.41:

| Phase                                   | Time   |
|-----------------------------------------|--------|
| Process spawn + dyld + adb client init  | ~75 ms |
| Connect to local adb-server (port 5037) | ~5 ms  |
| Phone roundtrip (empty file)            | ~30 ms |
| **Total**                               | **~110 ms** |

For the 1 GB file scenario: 1024 × 110 ms = **~110 seconds of pure subprocess + connect overhead** before any byte of payload moves.

### Why macDroid feels faster

Working assumptions (closed source, but observable from `ps`, `lsof`, packet captures, and the macDroid forum):

- **Long-lived ADB sync-protocol connection.** macDroid speaks the adb wire protocol (port 5037 → `host:transport:<serial>` → `sync:`) on a persistent socket — no `adb` CLI fork per operation. Each file is a single `RECV` command with streaming `DATA` chunks coming back inline.
- **Streamed reads, not chunked.** They open the file once, read in 32–64 KiB chunks from the same socket, write directly to the destination. No temp file staging.
- **Bundled with macFUSE / native Mount API.** When using the FUSE backend, they cache reads page-by-page in the kernel — random-access into the same file doesn't re-fetch.
- **Parallel transfers.** Multi-file copies fan out to N parallel sync streams (configurable; 3–5 typical).
- **Probably native libmtp integration**, calling `LIBMTP_Get_File_To_Handler` (streaming callback API) instead of subprocess wrapping.

---

## 2. Improvement tiers

Ordered by effort/impact. Each tier delivers value standalone — pick a stopping point.

### Tier 0 — Quick wins (1 day, ~50–100× on large files)

The single highest-impact fix is **stop calling `transport.read` in a chunked loop and instead call a one-shot pull-to-URL**.

**A0.** Add `transport.fetchTo(_ path: RemotePath, dest: URL, progress:) async throws` on `Transport`. Implementation calls a single `adb pull` and streams stdout progress via `runStreaming`. The IPC layer carries the destination temp URL string both ways.

**A1.** Rewrite `FreeDroidProviderExtension.fetchContents` to:
```swift
let tempURL = …
try await transport.fetchTo(path, dest: tempURL, progress: progress.completedUnitCount)
completionHandler(tempURL, item, nil)
```
**Expected speedup for a 1 GB file: ~100×** (no more 1024-fold redundant pulls).

**A2.** Same fix in `TransferEngine.pull`.

**A3.** For uploads: `transport.uploadFrom(_ url: URL, to path: RemotePath, progress:)` — single `adb push` from the URL the caller already has. Drops the `Data → temp → push` double-buffer.

**A4.** MTP chunked write — implement looped `LIBMTP_Send_File_From_Handler` instead of throwing on size > `maxWriteChunkBytes`. **Unblocks all MTP uploads >256 KB.**

**Risk:** low. Same `adb pull` / `adb push` invocations as terminal use; well-understood behavior; only the orchestration shape changes.

### Tier 1 — Local cache layer (2 days, big win on repeated access)

Even after Tier 0, Quick Look on a 200 MB MOV would pull it once. The second preview would pull it again. Apple's File Provider asks for `fetchContents` repeatedly under various conditions (item-attribute refresh, snapshot navigation, etc.).

**B1.** Add a content-addressable cache: `~/Library/Caches/FreeDroid/Content/<deviceID>/<sha-of-(path, mtime, size)>/<filename>`. After a successful pull, copy/hardlink the file into the cache.

**B2.** `fetchContents` checks the cache before pulling. Cache hits return instantly with the existing URL.

**B3.** LRU eviction at 10 GB default cap; configurable in Settings. Eviction respects `NSFileProviderManager.evictItem` so Finder can also drop entries.

**Risk:** medium. Cache invalidation is famously hard; we key by `(path, mtime, size)` which works for "did the file change on the device" but misses edge cases where mtime is reset (zip-extract-with-same-mtime, etc.).

### Tier 2 — Streaming reads / range requests (2 days, mid-file Quick Look)

Some files (PDFs, videos, big logs) only need the *start* of the file for the preview. Currently we pull the whole thing.

**C1.** Add `transport.fetchRange(_ path: RemotePath, offset: Int64, length: Int, dest: URL)` that pulls only the requested byte range. ADB sync protocol supports random access via `STAT` + `RECV` with offset (the `dd` trick on the device, or a small companion helper).

**C2.** `fetchContents` honors `requestedVersion?.fetchPosition` if provided; otherwise full file.

**Risk:** medium-low. Standard adb has no `pull --offset`; we'd implement it via `adb shell dd if=… skip=… bs=… count=…` which is reliable but adds shell overhead. The Tier 3 native protocol client makes this trivial.

### Tier 3 — Native ADB sync-protocol client (3–4 days, the big architecture win)

Replace subprocess `adb` calls with a **Swift-native client that speaks the wire protocol** to the local `adb-server` on `127.0.0.1:5037`. The adb server itself stays the bundled binary running once per app launch.

**Protocol specification:** [`SERVICES.TXT`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/SERVICES.TXT) and [`SYNC.TXT`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/SYNC.TXT). Stable for 14+ years.

**D1.** `Sources/FreeDroidADB/Wire/` — new submodule.
- `ADBWireConnection` — opens TCP to `127.0.0.1:5037`, handles the simple length-prefixed message format (`HHHHcommand`).
- `ADBSyncClient` — implements `STAT2`, `LIST`, `LISTV2`, `SEND`, `RECV` against an open `sync:` channel.
- `ADBHostClient` — `host:devices`, `host:transport:<serial>`, version, kill-server.

**D2.** Replace `LiveADBRunner` calls for list / stat / read / write with wire-protocol equivalents:

| `LiveADBRunner` call              | Wire equivalent                              | Latency drop |
|-----------------------------------|----------------------------------------------|--------------|
| `adb -s X shell ls -alL /sdcard/` | `host:transport-id:N`+`sync:`+`LIST`        | 110 ms → 5 ms |
| `adb -s X pull /sdcard/foo /tmp/y`| `RECV`+streamed `DATA` writes to URL        | 110 ms + N×80 ms → 5 ms + 1×stream |
| `adb -s X push /tmp/y /sdcard/foo`| `SEND` + streamed `DATA` from URL           | same |
| `adb -s X shell mkdir/rm/mv`      | `shell:` channel (still subprocess-shaped, but on socket) | 110 ms → 8 ms |

**D3.** Keep `runner.run(.startServer)` (and `killServer`) — we still need the adb-server process; we just stop talking to it via CLI.

**D4.** Cancellation: `URLSession`-style task handles that close the socket on `Task.cancel()` instead of `process.terminate()`.

**Expected end-to-end speedup vs current code on a 100 MB file:**

| Stage          | Now            | Tier 3         |
|----------------|----------------|----------------|
| List `/sdcard` | ~150 ms        | ~10 ms         |
| Pull 100 MB    | 110 ms + ~12 s | 5 ms + ~10 s   |
| Repeat-pull    | 12 s every time| Cache hit (Tier 1) |

**Risk:** medium-high. Implementation is well-documented but extensive (~600 LOC Swift); error handling and the binary framing aren't forgiving. Worth pairing it with an isolated test suite using a stubbed adb-server. Also unblocks: Wi-Fi-ADB-without-pair (we can talk directly to phone IP on port 5555), background-process-free operation (no `adb` subprocess on launch), and proper progress reporting (sync protocol delivers `DATA` packets with sizes).

### Tier 4 — Parallel transfers (1 day on top of Tier 3, big win on multi-file copies)

Tier 3 makes parallelization safe because we have explicit connection pooling.

**E1.** `TransferEngine` runs N concurrent `pull/push` operations against the same device (default N=3). Each opens its own `sync:` channel via a shared `ADBWireConnection`. ADB server multiplexes happily.

**E2.** Per-device serial queue (so we don't open 50 sync channels simultaneously to one phone) but cross-device parallel.

**E3.** Per-task progress aggregated to the per-transfer `Progress` object so the UI shows real percentages even with parallel children.

### Tier 5 — Compression (1 day, helps text/log files)

**F1.** Add the `--zstd` flag to `adb pull/push` invocations (or the equivalent in our wire client). Speeds up text/log/source-code transfers ~2–3×; minimal effect on already-compressed media. Requires Android 13+ on the phone (silent fallback for older).

### Tier 6 — MTP transport rewrite (3 days, parity with macDroid on no-debug phones)

The current MTP code wraps libmtp in subprocess-shaped synchronous calls. libmtp's actual API is callback-based and streaming.

**G1.** Rewrite `MTPSession.read/write` to use `LIBMTP_Get_File_To_Handler` / `LIBMTP_Send_File_From_Handler` with our own progress + cancellation callbacks. Single-shot per file, no chunk limits.

**G2.** Implement folder listing via `LIBMTP_Get_Files_And_Folders` (streaming, not the current eager full-tree call).

**G3.** Add `LIBMTP_Set_Storage` switching so we can browse phones with multiple storage roots (typical for Sony / Sharp).

**Risk:** medium. libmtp's C callbacks need careful Sendable bridging; the existing `CLibmtp` shim probably needs extending.

---

## 3. Framework-level recommendations

### Talk to Apple's File Provider better

We currently treat every fetch as a fresh download. Apple's API has machinery to do better:

- **`NSFileProviderItem.contentsURL`** — if we return a local URL alongside `fetchContents`, the file is treated as already-materialized; the system doesn't re-fetch on subsequent opens.
- **`NSFileProviderManager.evictItem`** — gives us back disk space when needed without losing metadata.
- **`NSFileProviderItem.fileSystemFlags`** — `.userImmutable` / `.userDoNotMaterialize` can hint to Finder which files shouldn't be greedily downloaded.
- **`NSFileProviderItem.itemVersion.contentVersion`** must be stable for the same content. Today we use `"c:\(mod):\(size)"` which is okay but if mtime is unset (often for libmtp roots) we get `c:0.0:0` for everything → version collisions → wrong cache hits. Fix: include path hash in the version.
- **Working-set materialization** — `materializedExtensions` API tells the system which already-pulled files don't need re-fetching when the user opens them again.

### Sparkle-aware temp directory

Tier 1's cache should live under `~/Library/Caches/FreeDroid/` (not `FileManager.temporaryDirectory`) so macOS doesn't purge it on disk pressure mid-transfer.

### Progress reporting

`Progress` instances are wired through but with poor granularity. Tier 3's wire client emits real per-byte progress; Tier 0 still reports per-chunk. Either way: `Progress.localizedAdditionalDescription` should be set ("Copying IMG_0042.jpg") so Finder's tooltip is useful.

### Sandbox / entitlements

If we eventually do Tier 3 (wire-protocol client to localhost:5037), the **bridge XPC service already has `network.client`**. No new entitlements needed.

For Tier 6 (libmtp rewrite), we already bundle libmtp; the rewrite is pure-Swift wrapping.

---

## 4. Recommended sequence

For maximum ROI per day spent:

```
Day 1   Tier 0 — pull-to-URL one-shot          [100× on big files, ships today]
Day 2   Tier 0 cont. — push-from-URL + MTP chunked writes
Day 3-4 Tier 1 — local cache                   [eliminates re-fetch tax]
Day 5-8 Tier 3 — native wire-protocol client   [the big arch win]
Day 9   Tier 4 — parallel transfers
Day 10  Tier 5 — zstd compression
Day 11+ Tier 6 — MTP rewrite
```

Tier 2 (range requests) becomes free once Tier 3 lands, so skip it as a standalone step.

After Day 1 you stop "waiting a lot" on individual files. After Day 8 you're at macDroid parity. After Day 10 you're probably ahead on common workloads.

---

## 5. Tests to add along the way

- **Performance regression test** (`Tests/FreeDroidADBPerfTests/`): stub adb-server speaking the wire protocol; assert that a `fetchContents` on a 100 MB file results in *one* `RECV` command, not N.
- **Cache correctness**: write the same file twice with the same `(path, mtime, size)` → second call is a cache hit. Change mtime → cache miss.
- **Cancellation**: cancel mid-transfer → socket closed, no temp file left behind, no zombie process.
- **Concurrent transfers**: 5 parallel pulls of different files via the same `ADBWireConnection` → all complete with correct content.
- **MTP chunked write**: 100 MB file via libmtp → arrives intact on the device.

---

## 6. What we can ship in the next hour vs the next week

**Hour-scale win (Tier 0 only, ~20 LOC change):**

The `fetchContents` loop becomes a single call:

```swift
func fetchContents(...) -> Progress {
    let progress = Progress(totalUnitCount: -1)
    Task {
        guard let path = ItemIdentifier.decode(itemIdentifier.rawValue) else { … }
        let entry = try await transport.stat(path)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        progress.totalUnitCount = entry.sizeBytes ?? -1
        try await transport.fetchTo(path, dest: tempURL, progress: progress)
        completionHandler(tempURL, ProviderItem(entry: entry, parent: path.parent ?? .root), nil)
    }
    return progress
}
```

`transport.fetchTo` runs **one** `adb pull` to the given URL. Progress comes from `adb pull`'s stderr (`[ 12%] /sdcard/foo`) parsed line by line.

This alone removes the O(n²) and makes a 1 GB file transfer take ~12 seconds instead of ~3 minutes.

**Week-scale win:** Tiers 0 → 3, plus the cache, plus MTP rewrite — the full arch upgrade.

---

## 7. Open questions for you

1. **Tier 0 only, or commit to the full arch upgrade?** Tier 0 alone is "good enough for most users this afternoon." The full upgrade is "we're now the best free option on macOS."
2. **Cache size default — 10 GB sane?** Or tie it to free disk space (e.g. 5% of free space)?
3. **Tier 4 default parallelism — 3? 5?** Bigger numbers help on USB-3 ADB; smaller on Wi-Fi-ADB (TCP head-of-line blocking).
4. **Should we add a "Speed test" diagnostic in Settings** that pulls a known 100 MB sentinel and reports MB/s, so users can compare to macDroid empirically?

---

*Plan author: Claude · Date: 2026-05-12 · Repo head: `12d7ae0`*
