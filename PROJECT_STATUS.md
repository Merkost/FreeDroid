# Project Status

A map of what's in the repo, what works, and what doesn't — written for someone landing in the codebase cold.

Last updated: 2026-05-12.

## Project structure

```
FreeDroid/                           SwiftUI app target (main host)
├── FreeDroidApp.swift                @main entry point
├── ContentView.swift                 Sidebar + Files/Gallery detail pane
├── AppContainer.swift                Composition root (DI graph)
├── Info.plist + entitlements
├── IPC/                              XPC server bridging app ↔ extension
├── Mount/                            MountCoordinator + FSExtensionMonitor + Store
├── Settings/                         Settings scene + AppPreferences
└── UI/                               FinderRevealer, SystemSettingsLauncher, FSExtensionBanner

FreeDroidFS/                          FSKit extension (.appex bundle)
├── Info.plist + entitlements         EXAppExtensionAttributes, FSSupportedSchemes
├── FreeDroidFSModule.swift           FSUnaryFileSystem subclass
├── FreeDroidVolume.swift             FSVolume + cache-backed lookup/enumerate
├── FreeDroidItem.swift               FSItem subclass
├── FreeDroidItemCache.swift          TTL cache, 45s
├── DirectoryEnumerator.swift         Paginated listing
├── XPCClient.swift                   Connects back to host app
├── ErrnoMapping.swift                TransportError → POSIX errno
└── VolumeIdentifierMint.swift        Stable per-device UUIDs

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
| **FreeDroidFS extension builds and embeds** | ✅ ExtensionKit `.appex` at `Contents/Extensions/`, registered by PluginKit |
| **ADB transport** | ✅ Bundled `adb` binary, device listing, file listing (symlinks resolved), push/pull, mkdir/rm/rename |
| **MTP transport** | ✅ libmtp + libusb (universal xcframeworks, `@rpath` linked), MTPSession implements Transport |
| **ADB vs MTP dedup** | ✅ Devices in both modes show as one card; MTP skipped when ADB has the descriptor |
| **USB hot-plug** | ✅ IOKit-based USBDeviceWatcher triggers immediate rescans |
| **`charging-only` and `pendingAuthorization` device states** | ✅ Distinct UI cards with hint text |
| **In-app file browser** | ✅ Browse, sort, rename, delete, mkdir on `/sdcard` and subdirs |
| **Photo gallery** | ✅ Masonry grid, async thumbnails, date sections |
| **Transfer queue** | ✅ Pull files to `~/Downloads/FreeDroid/<device>/` with progress, command strip, toasts |
| **UI design system** | ✅ Light + dark themes, motion presets, shadows token, snapshot tests |
| **Settings scene + persistent appearance** | ✅ Standard `Settings { … }`, `@AppStorage`-backed AppPreferences |
| **Reveal in Finder for transfer destinations** | ✅ Right-click on device card → "Reveal Transfers in Finder" |
| **One-click install** | ✅ Post-action on Run scheme auto-copies build to `/Applications/` |
| **CI baseline** | ✅ GitHub Actions workflows present (not yet verified against fresh clone) |

---

## What doesn't work — and why

### 1. Finder volume mount (`/Volumes/<Device>`)

**Status:** Code-side fixed. Remaining gate is a one-time per-user toggle.

**Symptom (before fix):** `mount: /Volumes/Pixel_9_Pro_XL: invalid file system`.

**Root cause:** `/sbin/mount -t freedroid …` defaults to the legacy VFS lookup at `/Library/Filesystems/freedroid.fs/Contents/Resources/mount_freedroid`. ExtensionKit-based FSKit extensions aren't installed there — they live as `.appex` bundles registered with `fskitd`. The `-F` flag tells `mount(8)` to route through FSKit/`fskitd` instead.

**Fix:** `MountCoordinator` now invokes `/sbin/mount -F -t freedroid …`. With `-F`, fskitd takes over and the failure shifts from "invalid file system" to `Module com.merkost.freedroid.FreeDroidFS is disabled!` until the user toggles the extension on.

**User action still required:** Open System Settings → Login Items & Extensions → File System Extensions and toggle FreeDroid on (one-time per machine/account). The in-app banner now distinguishes `installedButDisabled` from `notLoaded` so the user gets the right prompt.

### 2. System Settings → File System Extensions toggle bounces back

**Status:** Fixed. Two underlying causes, both addressed:

1. **Team mismatch** (originally documented here): resolved by `Configs/Local.xcconfig` pinning `DEVELOPMENT_TEAM = P47X2292CM`. Cert `K7KLY2K5TR` matches that team.
2. **Hardened-runtime missing on the appex** — this was the real cause of the silent toggle rollback. `project.yml` set `ENABLE_HARDENED_RUNTIME: YES` only on the `FreeDroid` app target, not on `FreeDroidFS`. macOS silently rejects FSKit extensions without hardened runtime: System Settings flips the switch on and immediately back off, leaving no UI error. Verified via `codesign -d --verbose=2 …FreeDroidFS.appex | grep flags` showing `flags=0x0(none)` before the fix and `flags=0x10000(runtime)` after.

Both `project.yml` and the pbxproj now carry `ENABLE_HARDENED_RUNTIME = YES` for the appex.

### 3. The Finder integration banner showed "Not enabled" even when the extension was installed

**Status:** Fixed (commit `2a6ee2e`).

`FSExtensionMonitor` previously called `FSClient.shared.fetchInstalledExtensions`, which only returns system-installed FSKit extensions and does not return our user-installed `.appex`. The detection now checks for the bundled `Contents/Extensions/FreeDroidFS.appex` directly on disk.

### 4. The DEVELOPMENT_TEAM gets wiped on every `xcodegen` regen

**Status:** Fixed (commit `30e330b`).

The team ID now lives in `Configs/Local.xcconfig` (gitignored) referenced via `configFiles:` in `project.yml`. Survives every `Scripts/generate-project.sh` run.

### 5. `Scripts/install-to-applications.sh` happens after **every** build

**Cost:** Adds a few seconds to every ⌘B. Builds the app, copies to `/Applications/`, kills the running instance, re-registers with `pluginkit`.

**Mitigation:** Acceptable for now since FSKit testing requires the app to live in `/Applications/` (DerivedData paths can't enable system extensions). If the post-action becomes a development drag, the option is to gate it to Release config only by editing the scheme.

### 6. Apple's `mount_<freedroid>` helper binary doesn't exist

**Status:** Resolved — no helper needed. With `mount -F` the VFS lookup is bypassed entirely and the request is routed to fskitd, which talks to the `.appex` directly. The legacy `mount_<fs>` binaries are only used for kernel/VFS filesystems.

### 7. Logs at `subsystem == "com.merkost.freedroid"` show repeated rescans

**Symptom:** Every ~15s the registry rescans, MTP discovers the same Pixel, and the dedup correctly drops it (`MTP scan: 1 discovered, 1 owned by ADB, 0 emitted`). When mount fails it now backs off for 30s before retrying.

**Status:** This is by design. The periodic rescan is a safety net behind the USB attach/detach events. If logs feel noisy in dev, lower the rescan frequency in `DeviceRegistry`.

### 8. Sparkle in-app updates point at a placeholder feed URL

**Status:** Intentional. `SUEnableAutomaticChecks` is currently `false` in `FreeDroid/Info.plist`. Users can still manually trigger via the menu (which will 404 today). The release pipeline will flip the URL and the auto-check flag once an actual GitHub Pages-hosted appcast is live.

### 9. No notarization yet

**Status:** Pipeline exists in `Scripts/build-release.sh` and `.github/workflows/release.yml` but none of the GitHub Secrets are configured. Steps to enable are documented in `docs/release-runbook.md`.

---

## Recently shipped

- `dev` Empty in-app browser fix (`ls -alL` only) + `mount -F` for FSKit routing + disabled-state banner
- `2a6ee2e` Banner detects via bundled appex + mount via `/sbin/mount`
- `986f51c` One-click install to `/Applications` via scheme post-action
- `1067f81` MountCoordinator + ADB symlink fix
- `5020451` FreeDroidFS restructured as ExtensionKit `.appex`
- `701ee9a` libusb signing fix (bundle as xcframework, use `@rpath`)
- `30e330b` Gitignored `Configs/Local.xcconfig` for persistent team ID
- `dcec186` Plan #12 covering full FSKit implementation

See `git log --oneline` for the full history.

---

## Reference docs

- [`README.md`](README.md) — user-facing overview, build instructions
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — coding rules, signing setup
- [`docs/superpowers/specs/2026-05-12-freedroid-design.md`](docs/superpowers/specs/2026-05-12-freedroid-design.md) — full design spec
- [`docs/superpowers/plans/`](docs/superpowers/plans/) — 12 implementation plans
- [`docs/release-runbook.md`](docs/release-runbook.md) — release process + secrets list
