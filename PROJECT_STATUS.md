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
| **Finder integration** | ✅ NSFileProvider domain per device; appears in Finder Locations sidebar |
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

- `dev` File Provider migration (NSFileProviderReplicatedExtension, ProviderDomainCoordinator, full CRUD)
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
