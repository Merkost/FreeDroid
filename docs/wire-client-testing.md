# Wire-client live-device tests

The wire-client tests under `Tests/FreeDroidADBWireTests/` ship two suites:

- **Unit tests** (always run) — exercise the protocol decoders against hand-crafted byte buffers and a Swift-NIO stub `adbd`. These never touch a real device.
- **Live-device tests** in `LiveDeviceTests.swift` — gated by an env var so CI doesn't try to talk to a phone that isn't there.

## Running live tests

Plug in an authorized Android device (USB, ADB allowed) and run:

```sh
FREEDROID_LIVE_DEVICE=1 swift test --filter "Live device"
```

The suite uses `ADBServer.live()` to spawn the bundled `adb` server, picks the first device in `state == .device`, then exercises `listV2 /sdcard`, `statV2 /system/build.prop`, and a 1 MB SEND/RECV round-trip on `/sdcard/.freedroid-live-<uuid>.bin`.

## Toggling the wire client at runtime

When the unit + live tests are both green, flip the user setting on:

```sh
defaults write group.com.merkost.freedroid freedroid.useWireClient -bool true
```

Or use **Settings → Transfers → Use native ADB sync protocol** in the app. The setting is shared between the main app, the appex, and the bridge via the `group.com.merkost.freedroid` defaults suite, so all three pick it up at session open.

## Diagnosing protocol mismatches

Every framing-violation `throw` site carries:

- a short string identifying which decoder failed (e.g. `statV2 unexpected id 'XXXX'`),
- a 16-byte hex dump of the first bytes adbd actually sent.

When you see `ADB wire framing violation [foo] first bytes: aa bb cc dd ...` in a log, grep that prefix against the AOSP `file_sync_protocol.h` to identify the frame the device actually emitted.
