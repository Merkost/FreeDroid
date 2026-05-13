# FreeDroid Roadmap — Improvements Beyond Current State

> Snapshot taken after Tier 3 v2 (wire client) landed and the post-Tier-3 refactor pass. This is a forward-looking inventory of work that would meaningfully move FreeDroid: from "competitive with macDroid on listings" to "matches or beats macDroid on every dimension."

Each item lists impact, rough cost, and dependencies so they're easy to pick up out of order.

---

## A. Performance

### A1. Wire-client fetch/upload (Tier 3 part II)

**Where we are:** `ADBSession.fetch` / `upload` still spawn `adb pull` / `adb push` subprocesses. Per-file fork+exec+auth overhead is the largest remaining cost on big batches (~100ms per file baseline before bytes move).

**Change:** Route `fetch` and `upload` through `ADBSyncClient.send` / `recv` over the persistent socket, gated on `wireEnabled`. Reuse the same fallback dispatcher that `list/stat/read/write` already use.

**Expected impact:** 5–10× faster on small-file batches. The 2500-file copy that surfaced "Extension internal error" should finish in 1/5 the time once stable.

**Risks:** RECV/SEND streaming needs robust cancellation. Long files need progress-callback wiring through `TransferProgressSink`. Need live-device tests for at-least 1MB and 100MB payloads.

**Effort:** ~half day. Touches: `ADBSession.fetch/upload`, `ADBSyncClient.recv/send` (mostly already there), one new live test.

### A2. Persistent ADB sync-connection pool

**Where we are:** Every `wireList`/`wireStat`/etc. opens a fresh TCP socket to adbd, runs `host:transport:<serial>` + `sync:`, then closes. That's 4 round-trips of setup per request.

**Change:** Per-serial pool of warm sync connections (default 4). Methods check out a connection, run their command, return it. Closed only on cancel/disconnect.

**Expected impact:** Halves the latency of every wire-client call once a connection is warm. Plus, eliminates the "device not found" race we saw under high load (Section D2 of the recent ops post-mortem) since the pool persists across the burst.

**Risks:** Connection-state corruption if a previous request died mid-frame. Need a probe-and-discard mechanism. Bounded pool size to avoid socket exhaustion.

**Effort:** ~1 day. New `ADBConnectionPool` actor; `ADBSyncClient.open` becomes `pool.borrow()` + `pool.return()`.

### A3. Single-pass enumeration for batch fetches

**Where we are:** Finder enumerates a folder → we return entries with sizes. Then for each item Finder calls `item(for:)` separately → another stat. Then `fetchContents` does another stat (cached, but still serializes through actor). Each "Preparing to copy" pass walks the same folder multiple times.

**Change:** When `enumerateItems` records the cache, also pre-warm `inFlightStats` so subsequent `item(for:)` calls for those paths short-circuit without even an actor hop. Plus a debounced "enumeration replay" mode where successive `item(for:)` calls for siblings of an already-listed folder reuse the cached entries.

**Expected impact:** "Preparing to copy" on 1000-item folders drops from ~1s to ~50ms.

**Risks:** Cache staleness if user modifies the folder on the device mid-batch.

**Effort:** Half day. Touches: `EnumerationCache.swift`, `FreeDroidProviderExtension.item(for:)`.

### A4. zstd over the wire client

**Where we are:** Tier 5 added `adb pull -z zstd` for the legacy path. The wire client's `RECV` doesn't negotiate compression.

**Change:** `RCV2` request id wraps RECV with zstd. Decompress chunks in-stream via `Compression.framework` `compression_stream_init(COMPRESSION_STREAM_DECODE)`.

**Expected impact:** 1.5–2× faster for compressible content (text, source code, logs). Negligible for already-compressed media (JPEGs, MP4s).

**Risks:** Wrong feature detection breaks all transfers. Gate on `host-features` containing both `zstd_recv` and `zstd_send`.

**Effort:** ~1 day. Touches: `ADBSyncClient`, `Sources/FreeDroidADB/Compression/` (new).

---

## B. Correctness / robustness

### B1. Resume-on-cancel for partial transfers

**Where we are:** Finder cancel mid-copy aborts a 100MB pull at 50MB; next try restarts from 0.

**Change:** Keep the partially-written staging file on cancel. On retry, send `SEND`/`RECV` with `offset:` parameter (adbd 1.0.41+ supports this). Falls back to full re-pull on older daemons.

**Expected impact:** Cancellation feels safer; large transfers can survive USB unplug.

**Risks:** Partial files leaking if we cancel without cleanup hook firing. Need TTL on staging area to evict.

**Effort:** 1 day. Touches: `ADBSyncClient`, `ContentCache.swift`.

### B2. Concurrent-domain device disambiguation

**Where we are:** `ProviderDomainCoordinator.adoptExistingDomains` matches by regex heuristic. If two devices have similar serials, we may misroute.

**Change:** Store a sidecar `<serial>.json` in the group container with VID/PID/serial; coordinator reads it at adoption time and matches strictly.

**Expected impact:** No more rare misroute on multi-device setups; reliable "this card maps to this Finder mount" when 2+ phones share a vendor.

**Risks:** Sidecar drift if the appex writes and the app reads. Atomically write + rename.

**Effort:** Half day.

### B3. Proper folder upload (recursive)

**Where we are:** `createItem` only handles a single file or single-folder mkdir. Dragging a *folder* into the Finder mount silently does nothing meaningful.

**Change:** Detect `contentType == .folder` and walk the source URL, calling `transport.write` for each file, `transport.mkdir` for each subdir. Throttle with `FetchGate` so we don't spawn 1000 adb pushes.

**Expected impact:** Drag-and-drop a folder from Finder to phone "just works."

**Risks:** Symlinks (skip), special files (skip), huge folders (memory if we buffer).

**Effort:** Half day. Touches: `FreeDroidProviderExtension.createItem`.

### B4. Move semantics for cross-device copy

**Where we are:** The cross-device copy plan we wrote covers copy only. "Move" (copy then delete from source) was deferred.

**Change:** `MoveToDeviceUseCase` wraps `CopyToDeviceService` + `delete` on the source after success. New IPC verb to keep it atomic from the user's POV.

**Expected impact:** Matches macDroid's drag-and-drop semantics (default = move, ⌥ = copy).

**Effort:** Half day after A1 lands.

---

## C. UX / product

### C1. Dual-pane file browser

**Where we are:** Brainstormed in `2026-05-13-cross-device-copy.md`. The user picked single-pane for now. Worth revisiting once cross-device copy ships and people start asking for power-user features.

**Change:** Toggle in the FileBrowser toolbar. Each pane has its own device picker + breadcrumbs. Drag-and-drop between panes maps to `MoveToDeviceUseCase` / `CopyToDeviceUseCase`.

**Expected impact:** Matches Total Commander / macDroid Pro UX.

**Effort:** 2–3 days.

### C2. Live transfer panel with cancellation

**Where we are:** `TransfersPanel` exists but only shows local app-initiated transfers. Finder-initiated transfers are invisible to the user inside FreeDroid (only Finder shows them).

**Change:** Pipe `fetchContents` / `createItem` progress through a new `ProviderProgressBroadcaster` actor → IPC up to the main app → TransfersPanel. Each row shows source/dest, progress, ETA, cancel button.

**Expected impact:** Users see what's happening from one place. Cancel button works without going to Finder.

**Effort:** 1–2 days. Touches: IPC types, TransfersPanel, FreeDroidProviderExtension.

### C3. Thumbnail provider extension

**Where we are:** Finder shows generic file icons in the Quick Look column for media on the mounted volume because we don't provide thumbnails.

**Change:** Add a `NSFileProviderThumbnailing` extension target that, for JPEG/HEIC/MP4 items, downloads enough bytes to extract the embedded preview (EXIF thumbnail for photos, first I-frame for videos via AVAssetImageGenerator). Cache to disk.

**Expected impact:** Gallery view in Finder feels native.

**Effort:** 2 days. New target + bridge changes.

### C4. Per-device storage stats in the device card

**Where we are:** `DeviceInfo.storageCapacityBytes` / `storageFreeBytes` are declared but always `nil` in the ADB path.

**Change:** `df /sdcard` on session warmup; cache. Show "215 GB free of 512 GB" in the device card.

**Effort:** A couple hours.

---

## D. Architecture

### D1. Replace byte-streaming IPC with FD-passing

**Where we are:** Current IPC reads full file into `Data`, sends over XPC, writes to disk. For multi-GB files this is bad — both bridge and appex hold the whole file in RAM.

**Change:** Use `NSXPCConnection`'s file-handle support. Appex opens a writable URL, sends the FD to the bridge; bridge `dup2()`s into adb's output. No buffer.

**Expected impact:** Memory drops from O(file size) to O(64KB chunk). Enables transferring 10+ GB videos without thrashing.

**Risks:** XPC FD-passing has Apple-specific quirks; need careful Sendable handling.

**Effort:** 2 days. Big API change but well-bounded.

### D2. Wire client gets its own connection per session, not per request

**Where we are:** A2 (above) is the user-facing fix. Architecturally, `ADBSession` should own one warm `ADBWireConnection` to the bundled adb-server and multiplex sync/host/shell channels over it.

**Change:** Refactor `ADBSyncClient.open` to take a shared connection from `ADBSession`. Sub-channels (sync, shell) become async sequences over the same TCP socket using the existing ADB multiplexing protocol.

**Expected impact:** Cleaner architecture; eliminates connection-setup overhead.

**Effort:** 2 days.

### D3. Type-safe IPC instead of `IPCRequest` enum + `Data` blobs

**Where we are:** `IPCRequest` is a single Codable enum routed by `BridgeHandler.execute`. Each new IPC verb requires touching the enum, the handler, the host handler, and the `ProviderTransport` send-with-expected-type helper.

**Change:** Define `XPCFileServerProtocol` as a real `@objc` Swift protocol with one method per operation. NSXPCInterface configures argument/return types. Drop manual encode/decode dance.

**Expected impact:** Less boilerplate per new verb; type-checker enforces shape; easier to mock for tests.

**Effort:** Half day refactor; mostly mechanical.

---

## E. Distribution / DX

### E1. Notarized release builds with Sparkle auto-update

**Where we are:** `xcodegen` already wires Sparkle as a package dependency; not actually plumbed into the app.

**Change:** Bundle `SUUpdaterDelegate`, wire menu item "Check for Updates...", publish appcast feed on GitHub releases.

**Effort:** Half day after the first notarized build.

### E2. Public CI on every push

**Where we are:** No CI runner. Tests are local-only.

**Change:** GitHub Actions matrix: `swift test` on every push, build the `.app` on every tag.

**Effort:** A couple hours.

### E3. Test fixtures from real adbd captures

**Where we are:** Unit tests hand-craft byte buffers. Brittle to subtle protocol drift.

**Change:** Add `Tests/Fixtures/` with real bytes captured from `tcpdump -i lo0 port 5037` while running through scripted scenarios. Replay against the parsers.

**Effort:** 1 day.

---

## Suggested ordering

If picking one or two to do next:

1. **A1 (wire-client fetch/upload)** — biggest single perf win, follows naturally from the just-landed Tier 3 work.
2. **A2 (connection pool)** — eliminates the "device not found" race under high load AND speeds up everything.

Then **B3 (folder upload)** because it's a glaring functional gap users hit immediately.

Save D2 and D3 (architecture polish) for a calm week — they pay back in maintainability, not user-visible speed.
