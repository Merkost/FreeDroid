# Project Status

A map of what's in the repo, what works, and what doesn't — written for someone landing in the codebase cold.

Last updated: 2026-05-14. **v0.1.0 shipped 2026-05-13.**

## Project structure

```
FreeDroid/                           SwiftUI app target (main host)
├── FreeDroidApp.swift                @main entry point
├── ContentView.swift                 Sidebar + Files/Gallery detail pane
├── AppContainer.swift                Composition root (DI graph)
├── Info.plist + entitlements
├── IPC/                              XPC server bridging app ↔ extension
├── Settings/                         Settings scene + AppPreferences
└── UI/                               FinderRevealer

Sources/                              Swift package modules (single root Package.swift)
├── FreeDroidDomain/                  Entities, repository protocols, errors
├── FreeDroidUI/                      Design system: tokens, theme, components
├── FreeDroidADB/                     adb binary wrapper, sync protocol
├── FreeDroidMTP/                     libmtp wrapper, MTPSession (Transport impl)
├── FreeDroidData/                    Repos, caches, USB watcher, DeviceRegistry, transfers
├── FreeDroidIPC/                     XPC request/response types
├── CLibmtp/                          C interop shim for libmtp
└── Features/
    ├── DeviceManagement/             Sidebar, device cards, trust prompts
    ├── FileBrowser/                  Breadcrumb + file rows + ops
    ├── Gallery/                      Masonry grid, async thumbnails
    └── Transfer/                     Queue, panel, toast presenter

Tests/                                Per-module test targets
Vendor/
├── libmtp.xcframework                Universal arm64+x86_64 libmtp.dylib
└── libusb.xcframework                Universal libusb-1.0.0.dylib

Scripts/
├── generate-project.sh               Wrapper: xcodegen + pbxproj patch
├── install-to-applications.sh        Post-action: copies build to /Applications + pluginkit
├── patch-pbxproj-local-packages.py   Xcode 26 local-package compatibility fix
├── build-libmtp.sh                   Rebuild libmtp.xcframework from source
├── build-release.sh                  Sign + notarize + DMG pipeline (release only)
├── make-dmg.sh
└── sparkle-sign.sh                   Sparkle 2 EdDSA appcast signing

Configs/
├── Local.xcconfig.example            Template for signing config
└── Local.xcconfig                    Gitignored, per-contributor DEVELOPMENT_TEAM

docs/
├── superpowers/specs/                Design spec (architecture, modules, UI, etc.)
├── superpowers/plans/                Implementation plans (12 files, one per sub-project)
└── appcast.xml                       Sparkle update feed (placeholder)

.github/
├── workflows/                        ci.yml, release.yml, homebrew-cask.yml, update-adb.yml, update-libmtp.yml
└── release-please-config.json
```

---

## What works

| Area | Status |
|---|---|
| **App target builds and runs** | ✅ Signed with Apple Development cert, launches cleanly |
| **v0.1.0 DMG published** | ✅ <https://github.com/Merkost/FreeDroid/releases/tag/v0.1.0> (unsigned dev build; notarization pipeline ready but unconfigured) |
| **Finder integration** | ✅ NSFileProvider domain per device; appears in Finder Locations sidebar |
| **ADB transport** | ✅ Bundled `adb` 1.0.41, device listing, file listing (symlinks resolved), push/pull, mkdir/rm/rename |
| **Native ADB wire-protocol client (Tier 3)** | ✅ Persistent `NWConnection` socket replaces per-call `adb` subprocess. LIST_V2 / STAT_V2 with V1 fallback. `host-features` negotiation; `shell_v2` gating. Default-on, kill-switch in Settings. Live-tested against Pixel. |
| **Wire connection pool** | ✅ Per-device `ADBSyncConnectionPool` keeps 4 warm sockets, evicts idle >60s. Eliminates per-call TCP+handshake roundtrip. |
| **Graceful wire→legacy fallback** | ✅ Any wire-level error transparently falls back to `adb` subprocess. Throttled log line. |
| **Session reuse across rescans** | ✅ `DeviceRegistry.rescan` reuses existing `ADBSession`/`MTPSession` per device. Cached `info`, `host-features`, warm pool, all preserved. |
| **MTP transport** | ✅ libmtp + libusb (universal xcframeworks, `@rpath` linked), MTPSession implements Transport. Now populates storage stats from `LIBMTP_Get_Storage`. |
| **ADB vs MTP dedup** | ✅ Devices in both modes show as one card; MTP skipped when ADB has the descriptor |
| **USB hot-plug** | ✅ IOKit-based USBDeviceWatcher triggers immediate rescans |
| **Disconnected device state** | ✅ During the 30s rescan-grace, devices flip to `.disconnected` (greyed out, not browsable) instead of looking ready. Selection auto-drops to next ready device. |
| **`charging-only` and `pendingAuthorization` device states** | ✅ Distinct UI cards with hint text |
| **Storage bar on device card** | ✅ Capacity / free read from `df /sdcard` (ADB) or libmtp storage list (MTP). Bar tints amber at 85%, red at 95%. |
| **In-app file browser** | ✅ Browse, sort, rename, delete, mkdir on `/sdcard` and subdirs |
| **Photo gallery** | ✅ Masonry grid, async thumbnails (ImageIO-based, thread-safe), date sections |
| **Transfer queue** | ✅ Pull AND push, direction-aware. Per-device parallelism (configurable). Progress reporting through the wire client. |
| **Finder copy: in-flight cache + invalidation** | ✅ EnumerationCache for sub-ms stats during Preparing-to-copy. createItem/modifyItem/deleteItem invalidate parent + signal Finder. notFound auto-evicts stale entries. |
| **Wi-Fi ADB pairing** | ✅ Pair via `adb pair host:port` + 6-digit code; persisted endpoints auto-reconnect on launch |
| **Menu-bar status item** | ✅ Always-visible icon (swaps to transfer glyph on active copies). Click → device list + "Reveal in Finder" per device + Open / Quit shortcuts. |
| **UI design system** | ✅ Light + dark themes, motion presets, shadows token, snapshot tests |
| **Settings: parallelism + wire toggle + theme** | ✅ Standard `Settings { … }`, shared `group.com.merkost.freedroid` UserDefaults suite so appex + bridge see the same values |
| **Reveal in Finder for transfer destinations** | ✅ Right-click on device card → "Reveal Transfers in Finder" |
| **Periodic temp purge** | ✅ Bridge sweeps stale `freedroid-adb-*` and `freedroid-bridge-*` files older than 1 hour on startup and every 15 min |
| **One-click install** | ✅ Post-action on Run scheme auto-copies build to `/Applications/` |
| **Adb subprocess cancellation** | ✅ `withTaskCancellationHandler` + `ProcessBox` actually terminates the subprocess on `Task.cancel()` |
| **ADB stat optimization** | ✅ Single-file `stat -c` replaces per-stat `ls -alL <parent>`. In-flight stat coalescer dedupes 8 concurrent identical stats to 1 subprocess. |
| **CI** | ✅ GitHub Actions workflows present, runs `swift test` on push to main + dev |

---

## What doesn't work — and why

### Finder integration via NSFileProviderReplicatedExtension

Devices appear in Finder under **Locations** as soon as ADB authorization completes. Each ready device is registered as an `NSFileProviderDomain` by `ProviderDomainCoordinator` in the host app; macOS spawns one `FreeDroidProviderExtension` process per domain. CRUD is wired (list, fetch, create, rename, replace, delete).

No System Settings toggle, no `/Volumes` mount, no FSKit appex, no macFUSE. Third-party FSKit on macOS 26 is broken (see <https://github.com/andrewgazelka/loaf/issues/1>); we use the File Provider framework instead, the same one macDroid, Dropbox, iCloud Drive use.

### 1. The DEVELOPMENT_TEAM gets wiped on every `xcodegen` regen

**Status:** Fixed (commit `30e330b`).

The team ID now lives in `Configs/Local.xcconfig` (gitignored) referenced via `configFiles:` in `project.yml`. Survives every `Scripts/generate-project.sh` run.

### 2. `Scripts/install-to-applications.sh` happens after **every** build

**Cost:** Adds a few seconds to every ⌘B. Builds the app, copies to `/Applications/`, kills the running instance, re-registers with `pluginkit`.

**Mitigation:** Acceptable for now since File Provider testing requires the app to live in `/Applications/` (DerivedData paths can't register provider extensions). If the post-action becomes a development drag, the option is to gate it to Release config only by editing the scheme.

### 3. Logs at `subsystem == "com.merkost.freedroid"` show repeated rescans

**Symptom:** Every ~15s the registry rescans, MTP discovers the same Pixel, and the dedup correctly drops it (`MTP scan: 1 discovered, 1 owned by ADB, 0 emitted`).

**Status:** This is by design. The periodic rescan is a safety net behind the USB attach/detach events. If logs feel noisy in dev, lower the rescan frequency in `DeviceRegistry`.

### 4. Sparkle in-app updates point at a placeholder feed URL


**Status:** Intentional. `SUEnableAutomaticChecks` is currently `false` in `FreeDroid/Info.plist`. Users can still manually trigger via the menu (which will 404 today). The release pipeline will flip the URL and the auto-check flag once an actual GitHub Pages-hosted appcast is live.

### 5. No notarization yet

**Status:** Pipeline exists in `Scripts/build-release.sh` and `.github/workflows/release.yml` but none of the GitHub Secrets are configured. Steps to enable are documented in `docs/release-runbook.md`.

---

## Recently shipped

### v0.1.0 (2026-05-13) — first public release

DMG: <https://github.com/Merkost/FreeDroid/releases/tag/v0.1.0>. 90 commits squashed onto main as PR #1. Highlights: NSFileProvider migration (from broken third-party FSKit), native ADB wire-protocol client (Tier 3) with full LIST_V2 / STAT_V2 / RECV / SEND parsers, persistent connection pool, transfer-performance work (one-shot pull/push, content cache, parallelism, zstd, MTP streaming).

### Post-v0.1.0 on `dev` (22 commits)

Behaviour fixes (user-visible):

- `0cf0067` New `.disconnected` device state — phones immediately greyed out on unplug instead of staying clickable during the 30s rescan-grace.
- `b6c25a8` MTP devices now show a populated storage bar (`LIBMTP_Get_Storage`).
- `a3b2875` `TransferProgressSink` name-collision fix — `ADBSession.fetch` now actually satisfies the `Transport` protocol witness.
- `0b05991` Thumbnail downscale moved to thread-safe ImageIO (was crashing with `EXC_BAD_ACCESS` in `NSImage.draw(in:)`).
- `52d9eec` `notFound` from transport evicts the appex's `EnumerationCache` + signals Finder to re-enumerate (kills the "ghost item, error -36" loop).
- `db9cf0f` Successful `createItem` / `modifyItem` / `deleteItem` invalidate parent cache and signal enumerator (prevents 5-min ghost-listing on uploads).
- `4577083` Storage bar tints amber at 85%, red at 95%.
- `9e39655` About panel has real GitHub Source / Releases / Issues / License links.
- `56ce7b5` Menu-bar status item with device list + "Reveal in Finder" per device.
- `1297d72` Menu-bar icon swaps to transfer glyph when copies are in flight.

Stability + perf fixes:

- `4e80c48` `DeviceRegistry.rescan` reuses existing sessions instead of recreating every 15s (was dropping warm wire pool + caches on every heartbeat).
- `5b391da` `LiveADBRunner` dedupes `run` / `runWithStdin` + honors `Task.cancel()` (was leaving subprocesses running until natural completion).
- `0fe25a4` Plugged AsyncStream continuation leaks in `USBDeviceWatcher`, `DeviceRegistry`, `TransferQueue` (subscribers were never reaped on cancellation).
- `1fe25ad` Periodic 15-min temp-file purge on the bridge + wire-pool idle eviction (>60s).
- `05b1f00` ContentCache is real LRU now (was FIFO under the hood).
- `3dc274a` Backwards-compat decoder for v0.1.0 ContentCache `meta.json`.
- `034791b` `FetchGate` over-acquire race fix + broader wire-fallback (catches NWError/POSIXError, not just `ADBWireError`) + `fetchContents` linearized via `materialize` helper.

Hygiene / Swift 6 strict concurrency:

- `b91c80e` `ProviderItem` `@unchecked Sendable`; `MaterializeResult` clean.
- `7cf096a` Dropped redundant `nonisolated(unsafe)` on local `Progress` lets.

### What's deferred (still on the roadmap)

See `docs/superpowers/plans/2026-05-14-cleanup-v4.md` for the latest. Top of queue:

1. **F1** — in-app live transfer panel for Finder copies (biggest perceived-quality win).
2. **F2** — cross-device drag-and-drop, building on the wire client.
3. **A1** — type-safe IPC (replace `IPCRequest` enum + handler switch with a real `XPCFileServerProtocol` per-verb method).
4. **D1/D2** — notarized signed release pipeline (script and Actions workflow exist; need secrets configured).

See `git log --oneline` for the full history.

---

## Reference docs

- [`README.md`](README.md) — user-facing overview, build instructions
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — coding rules, signing setup
- [`docs/superpowers/specs/2026-05-12-freedroid-design.md`](docs/superpowers/specs/2026-05-12-freedroid-design.md) — full design spec
- [`docs/superpowers/plans/`](docs/superpowers/plans/) — 12 implementation plans
- [`docs/release-runbook.md`](docs/release-runbook.md) — release process + secrets list
