<div align="center">
  <a href="FreeDroid/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png">
    <img src="FreeDroid/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="180" alt="FreeDroid app icon">
  </a>

# FreeDroid

### Your Android. Your Mac. Your files. **No subscription.**

*The open-source, macOS-native file manager for Android — because you shouldn't pay rent to move a photo off your own phone.*

[![macOS](https://img.shields.io/badge/macOS-15.4%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![Build](https://img.shields.io/github/actions/workflow/status/merkost/FreeDroid/ci.yml?branch=main&label=build)](https://github.com/merkost/FreeDroid/actions)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Price](https://img.shields.io/badge/price-%240.00%20forever-brightgreen)](#)
[![Open source](https://img.shields.io/badge/closed%20source-no-purple)](#)

</div>

---

## The pitch

You plugged your Android into a Mac. You wanted to drag three photos off it. The web told you to:

- Install **macDroid** — *"7-day trial, then $19.95/year or $39.95 lifetime"*
- Or install **MacDroid Pro** — *another paywall*
- Or run **Android File Transfer** — Google quietly killed it in 2024
- Or learn `adb pull` from a forum post

So here's a fourth option:

> ✨ **FreeDroid.** Open-source. macOS-native. Free as in *take it, fork it, ship it, charge nothing for it.* You shouldn't have to pay a subscription to access files you already own.

Plug your phone in. The phone appears in Finder under **Locations**. Drag your photos. Done. That's the entire pitch.

---

## How it stacks up

|                            | **FreeDroid**            | macDroid Free          | macDroid Pro                 | Android File Transfer |
|----------------------------|--------------------------|------------------------|------------------------------|-----------------------|
| Price                      | **$0 forever**           | Free, **read-only**    | Paid subscription            | Free *(discontinued)* |
| Open source                | **MIT licensed**         | ❌                     | ❌                           | ❌                    |
| Finder integration         | ✅ Locations sidebar     | Limited                | ✅                           | ❌ standalone window  |
| Read & write               | ✅                       | **Read only**          | ✅                           | ✅                    |
| Quick Look preview         | ✅                       | ❌                     | ✅                           | ❌                    |
| Multi-device               | ✅                       | One                    | Multi                        | One                   |
| Wi-Fi ADB (no cable)       | ✅ *(experimental)*      | ✅                     | ✅                           | ❌                    |
| ADB + MTP transports       | ✅                       | ✅                     | ✅                           | MTP only              |
| Telemetry / phone-home     | **None**                 | Unknown                | Unknown                      | Google                |
| Sandboxed via File Provider| ✅                       | macFUSE required       | macFUSE required             | n/a                   |
| Works on macOS 26          | ✅                       | ✅                     | ✅                           | **Broken**            |

*macOS Tahoe (26) removed Android File Transfer's signing chain. FreeDroid was built fresh against the macOS 15.4 File Provider API — same one Dropbox, OneDrive, and iCloud Drive use — so it'll keep working when the next macOS lands.*

---

## What it does

Plug in your Android device, FreeDroid shows it in Finder's Locations sidebar — no System Settings toggle, no kernel extensions, no `macFUSE`, no nagware. Browse `/sdcard` directly, preview files with Quick Look, drag in either direction. ADB gives you full filesystem speed when USB Debugging is on; MTP handles devices that aren't in dev mode. Wi-Fi ADB pairing means you can also leave the cable in the drawer. Multiple devices show up simultaneously, each as its own location.

---

## Features

<table>
  <tr>
    <td>📂 <strong>Finder integration</strong><br>Device appears under Locations via <code>NSFileProviderReplicatedExtension</code>. No FSKit, no System Settings toggle, no reboot.</td>
    <td>⚡ <strong>ADB + MTP transports</strong><br>Bundled <code>adb</code> binary for full filesystem speed; libmtp for no-debug-mode devices. Auto-selects ADB when authorized.</td>
  </tr>
  <tr>
    <td>📶 <strong>Wi-Fi ADB pairing</strong><br>Leave the cable in the drawer. Pair once with the 6-digit code from <em>Wireless Debugging</em>, reconnect automatically forever after.</td>
    <td>🔍 <strong>Inspector side panel</strong><br>Thumbnails, metadata, Open and Show in Finder actions for any selected file.</td>
  </tr>
  <tr>
    <td>👁 <strong>Quick Look previews</strong><br>Hit Space on any file for the native macOS Quick Look — no transfer required first.</td>
    <td>🖼 <strong>Photo Gallery</strong><br>Masonry grid with async thumbnails, date sections, and a folder picker to scope your view.</td>
  </tr>
  <tr>
    <td>🗂 <strong>In-app file browser</strong><br>Sort, multi-select, rename, delete, mkdir. Breadcrumb navigation, keyboard shortcuts (⌘1/⌘2/⌘3, ⌘A, ⇧-click range).</td>
    <td>📤 <strong>Transfer queue</strong><br>Progress tracking, command strip, toast notifications. Files land in <code>~/Downloads/FreeDroid/&lt;device&gt;/</code>.</td>
  </tr>
  <tr>
    <td>🎨 <strong>macOS-native UI</strong><br>Big Sur materials, light & dark themes, motion presets. Built in SwiftUI with strict Swift 6 concurrency.</td>
    <td>🛡 <strong>Privacy by design</strong><br>Zero telemetry. Zero analytics. Zero phone-home. Your files never touch our (non-existent) servers — there are none.</td>
  </tr>
  <tr>
    <td>🔄 <strong>Sparkle in-app updates</strong><br>EdDSA-signed updates via Sparkle 2. No App Store gatekeeping, no DRM, no nagware popups.</td>
    <td>📖 <strong>MIT licensed</strong><br>Fork it. Ship it. Rebrand it. Charge for it if you want — you can't say the same about the paid competition.</td>
  </tr>
</table>

---

## Screenshots

<table>
  <tr>
    <td align="center">
      <img src="docs/screenshots/main-window.png" alt="Main window" width="380"><br>
      <em>Screenshots coming soon</em>
    </td>
    <td align="center">
      <img src="docs/screenshots/finder-integration.png" alt="Finder integration" width="380"><br>
      <em>Screenshots coming soon</em>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/screenshots/inspector.png" alt="Inspector panel" width="380"><br>
      <em>Screenshots coming soon</em>
    </td>
    <td align="center">
      <img src="docs/screenshots/gallery.png" alt="Photo gallery" width="380"><br>
      <em>Screenshots coming soon</em>
    </td>
  </tr>
</table>

---

## Supported devices

FreeDroid recognises **65+ Android OEM USB vendor IDs** — if your phone is on this list, it shows up in the sidebar as soon as it's plugged in (ADB if USB Debugging is on, MTP otherwise). Most popular brands are covered:

<table>
  <tr>
    <td><strong>Google</strong> · Pixel</td>
    <td><strong>Samsung</strong> · Galaxy</td>
    <td><strong>Xiaomi</strong> · Mi, Redmi, POCO</td>
    <td><strong>OnePlus</strong></td>
  </tr>
  <tr>
    <td><strong>Oppo</strong></td>
    <td><strong>Realme</strong></td>
    <td><strong>Vivo</strong></td>
    <td><strong>Huawei</strong></td>
  </tr>
  <tr>
    <td><strong>Honor</strong></td>
    <td><strong>Motorola</strong></td>
    <td><strong>Sony</strong> · Xperia</td>
    <td><strong>LG</strong></td>
  </tr>
  <tr>
    <td><strong>HTC</strong></td>
    <td><strong>ASUS</strong> · ROG, Zenfone</td>
    <td><strong>Lenovo</strong></td>
    <td><strong>Nothing</strong></td>
  </tr>
  <tr>
    <td><strong>Nokia / HMD</strong></td>
    <td><strong>TCL / Alcatel</strong></td>
    <td><strong>ZTE</strong></td>
    <td><strong>Tecno / Infinix</strong></td>
  </tr>
  <tr>
    <td><strong>Wiko / Tinno</strong></td>
    <td><strong>Hisense</strong></td>
    <td><strong>Sharp</strong></td>
    <td><strong>Kyocera</strong></td>
  </tr>
  <tr>
    <td><strong>Panasonic</strong></td>
    <td><strong>Pantech</strong></td>
    <td><strong>Coolpad</strong></td>
    <td><strong>Acer Mobile</strong></td>
  </tr>
  <tr>
    <td><strong>Archos</strong></td>
    <td><strong>BLU</strong></td>
    <td><strong>Cubot</strong></td>
    <td><strong>Doogee</strong></td>
  </tr>
  <tr>
    <td><strong>Wileyfox</strong></td>
    <td><strong>Highscreen</strong></td>
    <td><strong>BlackBerry</strong></td>
    <td>…and most generic Android tablets</td>
  </tr>
</table>

Don't see your brand? File an issue with the output of `system_profiler SPUSBDataType | grep -B1 'Vendor ID'` and we'll add it. The full table lives in [`Sources/FreeDroidData/USB/AndroidVendorIDs.swift`](Sources/FreeDroidData/USB/AndroidVendorIDs.swift) — PRs especially welcome.

---

## Quick start

```bash
git clone https://github.com/merkost/FreeDroid.git
cd FreeDroid
cp Configs/Local.xcconfig.example Configs/Local.xcconfig
# edit Configs/Local.xcconfig → set DEVELOPMENT_TEAM to your Apple Developer Team ID
open FreeDroid.xcworkspace
# press ⌘R
```

The Run scheme's post-action automatically copies the build to `/Applications/FreeDroid.app` and re-registers the File Provider extension — required because macOS won't accept provider extensions from DerivedData.

---

## Why this exists

Because in 2026, on a Mac, the answer to "*how do I get a single video file off my Android*" should not be **"open your wallet."**

Apple shipped `NSFileProviderReplicatedExtension` in macOS 11.3 for exactly this kind of integration. It's free. It's stable. It's the same API powering Dropbox, OneDrive, iCloud Drive. There is no technical reason a free, open-source file manager for Android can't be a first-class macOS citizen.

So this one is.

If you find it useful: **star the repo, file an issue, send a PR.** That's the only price.

---

## Under the hood

FreeDroid is three Darwin processes working together:

- **`FreeDroid.app`** — SwiftUI host (macOS 15.4+, Swift 6 strict concurrency). Runs `ProviderDomainCoordinator`, which registers one `NSFileProviderDomain` per authorized ADB device. Hosts the in-app browser, gallery, transfer queue, and inspector.
- **`FreeDroidProvider.appex`** — `NSFileProviderReplicatedExtension`. macOS spawns one instance per domain; each domain appears as a device in Finder under Locations. Handles list, fetch, create, rename, replace, and delete.
- **`FreeDroidBridge.xpc`** — XPC service embedded inside both the host app and the appex (`Contents/XPCServices/`). Spawns the bundled `adb` binary and serves IPC requests from the extension via `NSXPCConnection(serviceName:)`.

Swift packages under `Sources/` provide the domain (`FreeDroidDomain`), design system (`FreeDroidUI`), transports (`FreeDroidADB`, `FreeDroidMTP`), data layer (`FreeDroidData`), IPC types (`FreeDroidIPC`), and feature modules (`DeviceManagement`, `FileBrowser`, `Gallery`, `Transfer`).

```
FreeDroid.app
    │
    ├── FreeDroidBridge.xpc  ◄──── NSXPCConnection ────► FreeDroidProvider.appex
    │        │                                                      │
    │        └── adb (bundled binary)                   NSFileProvider framework
    │                                                               │
    └── Finder Locations sidebar ◄─────────────────────────────────┘
```

See [`PROJECT_STATUS.md`](PROJECT_STATUS.md) for the working / known-issue map.

---

## Building from source

**Requirements:**

- macOS 15.4 Sequoia or newer
- Xcode 26 or newer
- An Apple Developer Team ID (free or paid)
- An Android device with a USB cable (optional — the app builds and runs without one)

No additional tools are required for a standard build. `xcodegen` and `swiftlint` are only needed if you regenerate the `.xcodeproj` from `project.yml`.

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for coding rules, signing setup, commit conventions, and the PR workflow.

The shortest contribution: open `system_profiler SPUSBDataType`, find your phone's `Vendor ID`, file an issue if it isn't in [`AndroidVendorIDs.swift`](Sources/FreeDroidData/USB/AndroidVendorIDs.swift) yet. Five-minute fix, helps every future user of your brand.

---

## License

**MIT** — see [`LICENSE`](LICENSE). Use it. Modify it. Embed it in your product. Just keep the notice.

Third-party component licenses are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

---

## Credits

- [Sparkle](https://sparkle-project.org) — in-app software updates
- [libmtp](https://libmtp.sourceforge.net) / [libusb](https://libusb.info) — MTP transport (LGPL, dynamically linked)
- [Android Open Source Project](https://source.android.com) — bundled `adb` binary (Apache 2.0)

---

<div align="center">

**If FreeDroid saved you from a subscription, [⭐ the repo](https://github.com/merkost/FreeDroid).**

*That's the whole business model.*

</div>
