# Roadmap v2 — After the post-release cleanup pass

> Snapshot after the second refactor sweep + v0.1.0 ship. Earlier `2026-05-13-future-improvements.md` is partially stale: A1, A2, C4 landed; new bugs surfaced and got fixed. This doc catalogs what's left as of dev HEAD.

## Bugs already fixed in this pass

- `FetchGate` over-acquire race (release decrement vs new-caller increment).
- `withWireFallback` swallowed only `ADBWireError`; NWError / POSIX errors didn't trigger fallback.
- `fetchContents` defer-with-Task slot leak.
- `notFound` from a stale `EnumerationCache` entry surfaced as "error -36" forever; cache now evicts and signals enumerator.
- 200+ MB of `freedroid-adb-<uuid>` stale temp files leaked from crashed bridge processes; `ADBFileSync.purgeStaleTempFiles` sweeps at bridge startup.
- `ContentCache.trimIfNeeded` sorted by `fetchedAt` (FIFO), not LRU. Heavily-used items got evicted first.
- `MediaRepositoryImpl.downscale` crashed off-main with `EXC_BAD_ACCESS` in `NSImage.draw(in:)`. Switched to thread-safe `CGImageSource`/`CGImageDestination`.
- Swift 6 strict concurrency: `ProviderItem` now `@unchecked Sendable`; `MaterializeResult` clean.
- Storage bar tints amber/red based on fill level.

## Top candidates for next pass

### Functional

**F1 — In-app live transfer panel for Finder copies.** Today `TransfersPanel` only shows app-initiated transfers. Finder-initiated transfers (the common path) are invisible inside FreeDroid. Plumb `fetchContents` / `createItem` progress from the appex up to the main app via a side-channel XPC connection. Big perceived-quality win. ~1 day.

**F2 — Cross-device drag-and-drop.** Plan exists in `2026-05-13-cross-device-copy.md`. With A1 wire-client transfers landed, this is mostly orchestration: pull from source, push to dest, expose one composite progress. ~1 day.

**F3 — Recursive folder upload from Finder.** When Finder drops a folder, it issues per-item `createItem` calls. We handle each in serial through a single `FetchGate` slot. Parallelize via a per-job `TaskGroup` so a folder of 200 small files copies in seconds not minutes. ~half day.

**F4 — Resume-on-cancel for partial transfers.** Keep partial files; SEND/RECV with `offset:` on retry. Especially valuable for 1GB+ videos that fail near the end. ~1 day.

**F5 — Sparkle auto-update.** Wired in package dependencies, never plumbed into the app. Needs appcast hosting and a notarization-blessed CI release. ~half day + ops.

### Performance

**P1 — zstd on the wire client.** `RCV2` / `SND2` with `compression_stream_*` decode. Negligible for JPEG/MP4 but 2× on text/source/logs. ~1 day.

**P2 — Skip the `transport.stat` round-trip when enumeration cache is fresh.** `materialize` always stats even on cache hit. Already pretty cheap (3ms wire) but goes to zero with this. Minor.

### UX

**U1 — Empty state polish.** When a device is connected but has no files in the current folder, we show a blank list. Replace with a helpful "Drag files here to copy" placeholder. ~half day.

**U2 — Quick-look thumbnails in Finder via `NSFileProviderThumbnailing`.** Needs a new appex target. ~2 days; biggest UX upgrade in the queue.

**U3 — Settings copy / iconography polish.** The "Use native ADB sync protocol" toggle is now default-on and stable; soften the warning copy.

**U4 — Right-click "Show on device" action.** On a Finder mount, opens that file's parent folder in the Android Files app via `am start`. Useful when comparing what's where.

### Architecture / hygiene

**A1 — Type-safe IPC via NSXPCInterface.** The current `IPCRequest` enum + `Data` blob bag is brittle. Switch each verb to a real `@objc` protocol method with type-checked args. ~half day mechanical.

**A2 — Move `ADBFileSync.purgeStaleTempFiles` to a periodic timer.** Today it runs only at bridge startup. If the bridge runs all day with constant work, garbage accumulates between startups. ~hour.

**A3 — Health-check timer for the wire connection pool.** When connections idle past N seconds, send a `noop:` (or close gracefully) to detect half-open sockets. ~half day.

**A4 — Live-bytes test fixtures.** Capture real `adbd` exchanges via `tcpdump` and replay them through the parsers. Brittle-protocol insurance. ~1 day once we have the captures.

### Distribution

**D1 — Notarized signed release flow.** `Scripts/build-release.sh` is set up for Developer ID + notarization; needs the keychain profile + Apple ID credentials wired into local env or GitHub Actions secrets.

**D2 — Public CI on `main` + tag-triggered notarized DMGs.** `release.yml` already exists; needs secrets and a first successful run.

## Suggested next move

If you want one more big-impact UX commit: **F1 (in-app live panel for Finder copies)** — moves FreeDroid from "Finder shows progress" to "FreeDroid is the source of truth for what's happening with your devices." A single half-day session can land it.

If you want a low-risk perf win: **F3 (parallel folder upload)** — folks dropping a "Vacation Photos" folder of 200 JPEGs will feel it immediately.

If you want a one-evening visible win: **U1 + U3** — copy polish + empty states. Pure SwiftUI changes, no protocol risk.
