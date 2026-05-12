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

**Symptom:** Plugging in an authorized phone shows the device in the app sidebar and the in-app browser works, but no entry appears in Finder under `/Volumes/`.

**Root cause:** `mount(8)` on macOS rejects `freedroid` as a filesystem type:

```
mount: /Volumes/Pixel_9_Pro_XL: invalid file system
```

The kernel only recognizes types registered at `/System/Library/Filesystems/<name>.fs/` or `/Library/Filesystems/<name>.fs/`. Our FSKit extension is registered with PluginKit (visible via `pluginkit -mAvv -p com.apple.fskit.fsmodule`) but that registration is **not** the same as the kernel-level filesystem type registration that `mount` looks for.

We tried `NetFSMountURLSync` first — it returns `ENOTSUP` (45) because NetFS only handles SMB/AFP/NFS/WebDAV, not custom schemes.

**Open questions:**

- Is there an Apple-blessed in-process API for triggering a mount of a registered ExtensionKit FSKit extension? `FSClient` in the macOS 26 SDK only exposes `fetchInstalledExtensions`, not a mount call.
- Apple's own `com.apple.fskit.msdos.appex`, `exfat.appex`, `ftp.appex` are paired with `/System/Library/Filesystems/msdos.fs/` (etc.) helper bundles. Do third-party FSKit extensions need a similar helper installed at `/Library/Filesystems/freedroid.fs/`? If yes, that requires admin auth to install.
- Or does fskitd lazily register the type at the kernel level after first user-toggle in Settings — and is our Settings toggle currently broken (see #2)?

**Next steps:**

- Try shipping a minimal `freedroid.fs` registration bundle and install it via a helper tool on first launch.
- Or wait for Apple to document/expose the proper app-side mount entry point for ExtensionKit-based FSKit extensions on macOS 15.4+.

### 2. System Settings → Login Items & Extensions → File System Extensions toggle is greyed out

**Symptom:** The FreeDroid entry appears in System Settings, but clicking the toggle does nothing.

**Root cause:** Code signing identity vs provisioning profile team mismatch. The current build has:

```
Authority=Apple Development: Konstantin Merenkov (K7KLY2K5TR)   ← cert team
TeamIdentifier=P47X2292CM                                          ← profile team
```

macOS refuses to let the user enable a FSKit extension whose signing cert is from a different team than the provisioning profile.

**Fix in progress:** Add an Apple Development cert for team `P47X2292CM` via Xcode → Settings → Accounts → Manage Certificates → +. Once the cert and profile teams match, the toggle should respond.

This is a per-contributor setup step, not a code change. Once aligned, every signed build is internally consistent.

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

**Related to #1.** Apple's reference FSKit extensions have a corresponding `mount_msdos`, `mount_ftp` binary at `/System/Library/Filesystems/<x>.fs/Contents/Resources/`. We don't ship one. This may or may not be required for ExtensionKit-style modules — needs investigation alongside #1.

### 7. Logs at `subsystem == "com.merkost.freedroid"` show repeated rescans

**Symptom:** Every ~15s the registry rescans, MTP discovers the same Pixel, and the dedup correctly drops it (`MTP scan: 1 discovered, 1 owned by ADB, 0 emitted`). When mount fails it now backs off for 30s before retrying.

**Status:** This is by design. The periodic rescan is a safety net behind the USB attach/detach events. If logs feel noisy in dev, lower the rescan frequency in `DeviceRegistry`.

### 8. Sparkle in-app updates point at a placeholder feed URL

**Status:** Intentional. `SUEnableAutomaticChecks` is currently `false` in `FreeDroid/Info.plist`. Users can still manually trigger via the menu (which will 404 today). The release pipeline will flip the URL and the auto-check flag once an actual GitHub Pages-hosted appcast is live.

### 9. No notarization yet

**Status:** Pipeline exists in `Scripts/build-release.sh` and `.github/workflows/release.yml` but none of the GitHub Secrets are configured. Steps to enable are documented in `docs/release-runbook.md`.

---

## Recently shipped

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
