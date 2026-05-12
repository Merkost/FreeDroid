# FreeDroid

The free, open-source way to mount Android devices as native Finder volumes on macOS.

A modern alternative to [MacDroid](https://www.macdroid.app/) built on Apple's FSKit framework. Plug your phone in, see it in Finder, drag files in either direction.

> **Status:** Pre-alpha. The app builds, signs, and runs end-to-end on macOS 15.4+. Native Finder-mount integration is gated behind Apple's `com.apple.developer.fskit.fsmodule` entitlement (see [Signing](#signing) below).

## Features

- **USB transports**
  - **ADB** — fast, full filesystem access (requires USB debugging on phone)
  - **MTP** — works without dev options, via libmtp (LGPL, dynamically linked)
  - Auto-selects ADB when authorized, falls back to MTP
- **Two ways to browse**
  - In-app file browser and photo gallery (no entitlement needed)
  - Native Finder mount under `/Volumes/<Device>` via FSKit (entitlement required)
- **Multi-device** — handle several phones simultaneously, each as its own volume
- **Photo gallery** — masonry grid with thumbnails, date sections, Quick Look
- **Premium UI** — light + dark themes, living device cards, liquid transfer progress, floating command strip
- **Open source** — MIT, no telemetry, no paywall

## Requirements

- macOS 15.4 Sequoia or newer
- Xcode 16.3 or newer
- An Apple Developer account
- An Android device with a USB cable

## Build

```bash
git clone https://github.com/Merkost/FreeDroid
cd FreeDroid
brew install swiftlint xcodegen
Scripts/generate-project.sh
```

Open `FreeDroid.xcworkspace`, then **⌘B**. The scheme's post-action automatically installs the built app to `/Applications/FreeDroid.app` and re-registers the FSKit extension.

## Signing

Each contributor signs locally with their own team. Configuration lives in a gitignored file:

```bash
# Edit after the first run of Scripts/generate-project.sh:
Configs/Local.xcconfig
# Replace YOUR_TEAM_ID_HERE with your Apple Developer Team ID
```

For native Finder integration you'll need the `com.apple.developer.fskit.fsmodule` entitlement, granted by Apple Developer Support upon request. Without it the in-app file browser, gallery, and transfer features still work — only the `/Volumes/` mount is gated.

## Architecture

- Clean Architecture + MVVM with feature-vertical Swift Package modules
- Domain → Data → Presentation layers strictly enforced
- Swift 6 with strict concurrency from day one
- Single root `Package.swift` containing 10 library products (`FreeDroidDomain`, `FreeDroidUI`, `FreeDroidADB`, `FreeDroidMTP`, `FreeDroidData`, `FreeDroidIPC`, plus 4 feature packages)
- `FreeDroid.app` — main SwiftUI host
- `FreeDroidFS.appex` — ExtensionKit-based FSKit module (the Finder mount provider)

Full design at [`docs/superpowers/specs/2026-05-12-freedroid-design.md`](docs/superpowers/specs/2026-05-12-freedroid-design.md).

## Project layout

```
FreeDroid/              SwiftUI app target
FreeDroidFS/            FSKit extension (.appex)
Sources/                Swift packages (Domain, UI, ADB, MTP, Data, IPC, Features)
Tests/                  Per-module test targets
Vendor/                 Pre-built libmtp + libusb xcframeworks
Scripts/                Build helpers, xcodegen wrapper, libmtp builder
Configs/                Local signing config (gitignored)
docs/                   Design spec + implementation plans
```

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md). Key rules:

- No inline `//` comments — code is self-documenting (SwiftLint enforces)
- No `print` — use `os.Logger`
- TDD where the plan calls for it
- Conventional Commits (`feat:`, `fix:`, `chore:`, …)
- Swift 6 strict concurrency, zero warnings

## License

MIT — see [`LICENSE`](LICENSE).

Third-party components retain their own licenses; see `THIRD_PARTY_NOTICES.md` (generated at release).
