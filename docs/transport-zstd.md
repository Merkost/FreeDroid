# zstd Compression in ADB Transport

## Bundled adb version

FreeDroid bundles adb **1.0.41 (version 37.0.0-14910828)**. This version supports the `-z ALGORITHM` flag for both `adb pull` and `adb push`, with `zstd` as a valid algorithm choice.

## How it works

When the connected adb server advertises both `zstd_compress` and `zstd_decompress` in its feature set (returned by `host-features`), FreeDroid appends `-z zstd` to every `pull` and `push` invocation. The feature set is fetched once per `ADBSession` lifetime and cached.

Android 13+ devices running adb daemon 1.0.41+ will advertise these features. Older devices fall back to uncompressed transfers automatically because `ADBSession.zstdEnabled()` returns `false` when either feature is absent.

## Expected speedup

zstd typically yields a **2–3x throughput improvement** for compressible content (text files, source code, logs, SQLite databases). Already-compressed media (JPEG, MP4, APK, ZIP) see minimal benefit and no regression, because adb applies the flag per-transfer and zstd adapts to incompressible data gracefully.

## Requirements

| Requirement | Minimum |
|---|---|
| Bundled adb | 1.0.41 (already met) |
| Device Android version | 13 (API 33) for `zstd_compress`/`zstd_decompress` features |
| Device adb daemon | 1.0.41+ |

## Implementation references

- `ADBCommand.pull(compressed:)` / `ADBCommand.push(compressed:)` — emit `-z zstd` when `compressed == true`
- `ADBCommand.hostFeatures` — maps to `host-features` subcommand
- `ADBServer.features()` — fetches and caches the feature set for the session
- `ADBSession.zstdEnabled()` — checks `zstd_compress` and `zstd_decompress` in the feature set
- `ADBOutputParser.parseFeatures(_:)` — parses the comma-separated feature list
