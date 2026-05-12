# `adb` binary

This binary is `adb` from Google's Android Platform-Tools.

- **Source:** https://developer.android.com/tools/releases/platform-tools
- **License:** Apache License 2.0 (see `LICENSE-ADB.txt` at release-build time)
- **Update process:** `.github/workflows/update-adb.yml` runs weekly and opens a PR if a newer release ships.

We bundle this binary for convenience; users may override it via the `FREEDROID_ADB_PATH` environment variable when developing.
