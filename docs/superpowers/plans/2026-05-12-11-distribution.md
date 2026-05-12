# FreeDroid Plan #11 — Distribution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship FreeDroid: code-sign + notarize the app, package as a DMG, publish GitHub Releases, set up Sparkle 2 in-app updates with an EdDSA-signed appcast, automate Homebrew Cask submission, and generate `THIRD_PARTY_NOTICES.md` at build time.

**Architecture:** GitHub Actions workflow tagged on `v*.*.*` push that runs the full lint + test + build + sign + notarize + DMG + release + cask pipeline. Sparkle 2 appcast hosted on GitHub Pages branch. Signing identity stored in repo secrets. Notarization via `xcrun notarytool` with API key.

**Tech Stack:** GitHub Actions, `xcodebuild`, `codesign`, `notarytool`, `create-dmg`, Sparkle 2, Homebrew Cask, `git-cliff`, `release-please`.

---

## File Structure

```
.github/
├── workflows/
│   ├── release.yml                                     create — tag-triggered pipeline
│   ├── homebrew-cask.yml                               create — bumps homebrew/cask after release
│   ├── update-adb.yml                                  create — weekly adb update PR
│   └── update-libmtp.yml                               create — monthly libmtp xcframework rebuild
├── release-please-config.json                          create
└── .release-please-manifest.json                       create

Scripts/
├── build-release.sh                                    create — orchestrates build+sign+notarize
├── make-dmg.sh                                         create — DMG packaging
├── generate-third-party-notices.sh                     create
└── sparkle-sign.sh                                     create — signs appcast item with EdDSA

Resources/
├── dmg-background.png                                  manual asset
└── sparkle-public-key.pem                              committed

THIRD_PARTY_NOTICES.md                                  generated at build time
docs/appcast.xml                                        committed appcast skeleton
cliff.toml                                              create — git-cliff config
```

---

## Task 1: Set up `release-please` and `git-cliff`

**Files:**
- Create: `.github/release-please-config.json`
- Create: `.github/.release-please-manifest.json`
- Create: `cliff.toml`

- [ ] **Step 1: Configure release-please**

Write `.github/release-please-config.json`:

```json
{
  "release-type": "simple",
  "packages": {
    ".": {
      "release-type": "simple",
      "package-name": "FreeDroid",
      "include-v-in-tag": true,
      "changelog-sections": [
        { "type": "feat", "section": "Features" },
        { "type": "fix", "section": "Bug Fixes" },
        { "type": "perf", "section": "Performance" },
        { "type": "refactor", "section": "Refactors" },
        { "type": "docs", "section": "Documentation" },
        { "type": "chore", "section": "Chores", "hidden": true }
      ]
    }
  }
}
```

Write `.github/.release-please-manifest.json`:

```json
{ ".": "0.0.1" }
```

- [ ] **Step 2: Configure git-cliff**

Write `cliff.toml`:

```toml
[changelog]
header = "# Changelog\n"
body = """
## [{{ version }}] - {{ timestamp | date(format=\"%Y-%m-%d\") }}
{% for group, commits in commits | group_by(attribute=\"group\") %}
### {{ group | upper_first }}
{% for commit in commits %}
- {{ commit.message | upper_first }}{% endfor %}
{% endfor %}
"""

[git]
conventional_commits = true
filter_unconventional = true
commit_parsers = [
  { message = "^feat", group = "Features" },
  { message = "^fix", group = "Bug Fixes" },
  { message = "^perf", group = "Performance" },
  { message = "^refactor", group = "Refactors" },
  { message = "^docs", group = "Documentation" },
  { message = "^test", group = "Tests" },
  { message = "^chore", skip = true }
]
```

- [ ] **Step 3: Commit**

```bash
git add .github cliff.toml
git commit -m "chore: configure release-please and git-cliff"
```

---

## Task 2: Third-party notices generator

**Files:**
- Create: `Scripts/generate-third-party-notices.sh`

- [ ] **Step 1: Write the generator**

Write `Scripts/generate-third-party-notices.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT="THIRD_PARTY_NOTICES.md"

cat > "$OUT" <<'EOF'
# Third-Party Notices

FreeDroid uses the following third-party components.

---

## adb (Android Platform-Tools)

**License:** Apache License 2.0
**Source:** https://developer.android.com/tools/releases/platform-tools

A copy of the Apache 2.0 license is reproduced below.

---

## libmtp

**License:** GNU Lesser General Public License v2.1
**Source:** https://libmtp.sourceforge.io/

libmtp is dynamically linked in FreeDroid. The corresponding source is available at the URL above.

---

## libusb

**License:** GNU Lesser General Public License v2.1
**Source:** https://libusb.info/

libusb is dynamically linked via libmtp.

---

## swift-async-algorithms

**License:** Apache License 2.0
**Source:** https://github.com/apple/swift-async-algorithms

---

## swift-dependencies

**License:** Apache License 2.0
**Source:** https://github.com/pointfreeco/swift-dependencies

---

## swift-snapshot-testing

**License:** MIT
**Source:** https://github.com/pointfreeco/swift-snapshot-testing

---

## Sparkle 2

**License:** MIT
**Source:** https://sparkle-project.org/

EOF

echo "Wrote $OUT"
```

- [ ] **Step 2: Make executable, run, commit**

```bash
chmod +x Scripts/generate-third-party-notices.sh
Scripts/generate-third-party-notices.sh
git add Scripts THIRD_PARTY_NOTICES.md
git commit -m "chore: add third-party notices generator and initial notices"
```

---

## Task 3: Sparkle 2 integration

**Files:**
- Modify: `FreeDroid` target (add Sparkle package dependency)
- Create: `Resources/sparkle-public-key.pem`
- Create: `docs/appcast.xml`

- [ ] **Step 1: Add Sparkle package to the project**

In Xcode: File → Add Package Dependencies → `https://github.com/sparkle-project/Sparkle` → version 2.x → add to `FreeDroid` target.

- [ ] **Step 2: Generate EdDSA keypair**

Run:

```bash
mkdir -p /tmp/sparkle-keys
~/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys /tmp/sparkle-keys/private.pem /tmp/sparkle-keys/public.pem
```

Copy `public.pem` into the repo:

```bash
cp /tmp/sparkle-keys/public.pem Resources/sparkle-public-key.pem
```

Keep `private.pem` outside the repo. Add its contents as the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.

- [ ] **Step 3: Configure the app's `Info.plist`**

In `FreeDroid/Info.plist`, add:

```xml
<key>SUFeedURL</key>
<string>https://&lt;org&gt;.github.io/FreeDroid/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>%PUBLIC_KEY%</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

Replace `%PUBLIC_KEY%` at build time with the contents of `Resources/sparkle-public-key.pem` (base64-stripped, single line). The release workflow does this via a `sed` step.

- [ ] **Step 4: Integrate Sparkle into the app**

In `FreeDroid/FreeDroidApp.swift`, add:

```swift
import Sparkle

@MainActor
final class UpdaterController {
    let driver: SPUStandardUpdaterController

    init() {
        self.driver = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}

@main
struct FreeDroidApp: App {
    @State private var container = AppContainer()
    private let updater = UpdaterController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.driver.checkForUpdates(nil)
                }
            }
        }
    }
}
```

- [ ] **Step 5: Write the initial appcast**

Write `docs/appcast.xml`:

```xml
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>FreeDroid</title>
    <link>https://&lt;org&gt;.github.io/FreeDroid/appcast.xml</link>
    <description>Releases of FreeDroid</description>
    <language>en</language>
  </channel>
</rss>
```

- [ ] **Step 6: Commit**

```bash
git add FreeDroid Resources docs/appcast.xml
git commit -m "feat(release): integrate Sparkle 2 in-app updater"
```

---

## Task 4: DMG packaging script

**Files:**
- Create: `Scripts/make-dmg.sh`

- [ ] **Step 1: Install `create-dmg`**

Run: `brew install create-dmg` (locally, and add to CI via `brew install` in the workflow).

- [ ] **Step 2: Write the script**

Write `Scripts/make-dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: make-dmg.sh <version> <app-path> <output-dmg>}"
APP_PATH="${2:?}"
OUTPUT_DMG="${3:?}"

create-dmg \
  --volname "FreeDroid $VERSION" \
  --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$(basename "$APP_PATH")" 175 190 \
  --hide-extension "$(basename "$APP_PATH")" \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "$OUTPUT_DMG" \
  "$APP_PATH"

echo "Built $OUTPUT_DMG"
```

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x Scripts/make-dmg.sh
git add Scripts/make-dmg.sh
git commit -m "chore(release): add DMG packaging script"
```

---

## Task 5: Build/sign/notarize orchestration script

**Files:**
- Create: `Scripts/build-release.sh`

- [ ] **Step 1: Write the script**

Write `Scripts/build-release.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: build-release.sh <version>}"
BUILD_DIR="build/release"
APP_NAME="FreeDroid"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-freedroid-notary}"

rm -rf "$BUILD_DIR"

xcodebuild archive \
  -workspace FreeDroid.xcworkspace \
  -scheme FreeDroid \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$VERSION"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist Scripts/export-options.plist \
  -exportPath "$BUILD_DIR/Export"

EXPORT_APP="$BUILD_DIR/Export/$APP_NAME.app"

xcrun notarytool submit "$EXPORT_APP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$EXPORT_APP"

DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
Scripts/make-dmg.sh "$VERSION" "$EXPORT_APP" "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$DMG_PATH"

echo "Built $DMG_PATH"
```

- [ ] **Step 2: Add export options plist**

Write `Scripts/export-options.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

- [ ] **Step 3: Commit**

```bash
chmod +x Scripts/build-release.sh
git add Scripts
git commit -m "chore(release): add build/sign/notarize/DMG orchestration"
```

---

## Task 6: Sparkle appcast signing

**Files:**
- Create: `Scripts/sparkle-sign.sh`

- [ ] **Step 1: Write the signing helper**

Write `Scripts/sparkle-sign.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: sparkle-sign.sh <version> <dmg> <release-notes-url>}"
DMG_PATH="${2:?}"
NOTES_URL="${3:?}"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY_PATH:?SPARKLE_PRIVATE_KEY_PATH not set}"
TOOL="$HOME/Library/Developer/Xcode/DerivedData"
SIGN_TOOL="$(find "$TOOL" -name sign_update -type f -perm -u+x 2>/dev/null | head -n 1)"
if [ -z "$SIGN_TOOL" ]; then
  echo "Could not find sign_update; ensure Sparkle is checked out via SPM."
  exit 1
fi

SIGNATURE_OUT=$("$SIGN_TOOL" "$DMG_PATH" "$PRIVATE_KEY")

cat <<EOF
<item>
  <title>FreeDroid $VERSION</title>
  <link>$NOTES_URL</link>
  <sparkle:version>$VERSION</sparkle:version>
  <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>15.4</sparkle:minimumSystemVersion>
  <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S GMT")</pubDate>
  <enclosure
    url="https://github.com/<org>/FreeDroid/releases/download/v$VERSION/FreeDroid-$VERSION.dmg"
    sparkle:edSignature="$SIGNATURE_OUT"
    length="$(stat -f%z "$DMG_PATH")"
    type="application/octet-stream" />
</item>
EOF
```

- [ ] **Step 2: Commit**

```bash
chmod +x Scripts/sparkle-sign.sh
git add Scripts
git commit -m "chore(release): add Sparkle appcast item signing script"
```

---

## Task 7: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the workflow**

Write `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  release:
    runs-on: macos-15
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true
          fetch-depth: 0

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'

      - name: Install tools
        run: brew install create-dmg swiftlint

      - name: Determine version
        id: version
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Generate third-party notices
        run: Scripts/generate-third-party-notices.sh

      - name: Import signing certificate
        env:
          SIGNING_CERT_P12: ${{ secrets.SIGNING_CERT_P12 }}
          SIGNING_CERT_PASSWORD: ${{ secrets.SIGNING_CERT_PASSWORD }}
        run: |
          echo "$SIGNING_CERT_P12" | base64 --decode > /tmp/cert.p12
          security create-keychain -p "" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "" build.keychain
          security import /tmp/cert.p12 -k build.keychain -P "$SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" build.keychain

      - name: Store notarization credentials
        env:
          NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
          NOTARY_ISSUER_ID: ${{ secrets.NOTARY_ISSUER_ID }}
          NOTARY_PRIVATE_KEY: ${{ secrets.NOTARY_PRIVATE_KEY }}
        run: |
          echo "$NOTARY_PRIVATE_KEY" > /tmp/notary.p8
          xcrun notarytool store-credentials freedroid-notary \
            --key /tmp/notary.p8 \
            --key-id "$NOTARY_KEY_ID" \
            --issuer "$NOTARY_ISSUER_ID"

      - name: Build, sign, notarize, package DMG
        env:
          SIGNING_IDENTITY: ${{ secrets.SIGNING_IDENTITY }}
          DEVELOPMENT_TEAM: ${{ secrets.DEVELOPMENT_TEAM }}
          NOTARY_PROFILE: freedroid-notary
        run: Scripts/build-release.sh "${{ steps.version.outputs.version }}"

      - name: Store Sparkle private key
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          echo "$SPARKLE_PRIVATE_KEY" > /tmp/sparkle-private.pem
          chmod 600 /tmp/sparkle-private.pem

      - name: Sign appcast item
        env:
          SPARKLE_PRIVATE_KEY_PATH: /tmp/sparkle-private.pem
        run: |
          Scripts/sparkle-sign.sh \
            "${{ steps.version.outputs.version }}" \
            "build/release/FreeDroid-${{ steps.version.outputs.version }}.dmg" \
            "https://github.com/${{ github.repository }}/releases/tag/${{ github.ref_name }}" \
            > /tmp/appcast-item.xml

      - name: Update appcast
        run: |
          NEW_ITEM=$(cat /tmp/appcast-item.xml)
          python3 - <<PY
          import xml.etree.ElementTree as ET
          tree = ET.parse('docs/appcast.xml')
          root = tree.getroot()
          channel = root.find('channel')
          new_item_xml = '''$NEW_ITEM'''
          import xml.etree.ElementTree as ET2
          item = ET2.fromstring(new_item_xml.strip())
          channel.append(item)
          tree.write('docs/appcast.xml', xml_declaration=True, encoding='utf-8')
          PY

      - name: Commit appcast update
        run: |
          git config user.name "FreeDroid Release Bot"
          git config user.email "release-bot@freedroid.app"
          git add docs/appcast.xml
          git commit -m "release: appcast for v${{ steps.version.outputs.version }}" || echo "no changes"
          git push origin HEAD:main || echo "push failed"

      - name: Create GitHub release
        uses: softprops/action-gh-release@v2
        with:
          files: build/release/FreeDroid-${{ steps.version.outputs.version }}.dmg
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow with sign, notarize, DMG, appcast"
```

---

## Task 8: Homebrew Cask automation

**Files:**
- Create: `.github/workflows/homebrew-cask.yml`

- [ ] **Step 1: Write the workflow**

Write `.github/workflows/homebrew-cask.yml`:

```yaml
name: Homebrew Cask

on:
  release:
    types: [published]

jobs:
  bump-cask:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Bump cask
        uses: dawidd6/action-homebrew-bump-cask@v3
        with:
          token: ${{ secrets.HOMEBREW_GITHUB_TOKEN }}
          cask: freedroid
          tag: ${{ github.event.release.tag_name }}
          revision: ${{ github.sha }}
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/homebrew-cask.yml
git commit -m "ci: auto-bump Homebrew Cask on release"
```

---

## Task 9: Weekly adb update PR bot

**Files:**
- Create: `.github/workflows/update-adb.yml`

- [ ] **Step 1: Write the workflow**

Write `.github/workflows/update-adb.yml`:

```yaml
name: Update adb binary

on:
  schedule:
    - cron: '0 7 * * 1'
  workflow_dispatch:

jobs:
  update:
    runs-on: macos-15
    permissions:
      pull-requests: write
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Download latest Platform-Tools
        run: |
          curl -L -o /tmp/platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
          unzip -q /tmp/platform-tools.zip -d /tmp/
          cp /tmp/platform-tools/adb Packages/FreeDroidADB/Resources/adb
          chmod +x Packages/FreeDroidADB/Resources/adb

      - name: Verify
        run: Packages/FreeDroidADB/Resources/adb --version

      - name: Run ADB unit tests
        run: cd Packages/FreeDroidADB && swift test --parallel

      - name: Open PR
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          branch: chore/update-adb
          commit-message: "chore(adb): update bundled adb binary"
          title: "chore(adb): update bundled adb binary"
          body: "Weekly bot pulled latest Android Platform-Tools."
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/update-adb.yml
git commit -m "ci: weekly bot updating bundled adb binary"
```

---

## Task 10: Monthly libmtp xcframework rebuild

**Files:**
- Create: `.github/workflows/update-libmtp.yml`

- [ ] **Step 1: Write the workflow**

Write `.github/workflows/update-libmtp.yml`:

```yaml
name: Rebuild libmtp xcframework

on:
  schedule:
    - cron: '0 8 1 * *'
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15
    permissions:
      pull-requests: write
      contents: write
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'

      - name: Install build deps
        run: brew install autoconf automake libtool pkg-config

      - name: Rebuild xcframework
        run: Scripts/build-libmtp.sh

      - name: Run MTP unit tests
        run: cd Packages/FreeDroidMTP && swift test --parallel

      - name: Open PR
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          branch: chore/update-libmtp
          commit-message: "chore(mtp): rebuild libmtp xcframework"
          title: "chore(mtp): rebuild libmtp xcframework"
          body: "Monthly rebuild — verify on real Pixel/Samsung devices before merging."
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/update-libmtp.yml
git commit -m "ci: monthly libmtp xcframework rebuild bot"
```

---

## Task 11: Tag the first release

**Files:**
- Modify: `.release-please-manifest.json` (auto by bot)

This is a manual milestone.

- [ ] **Step 1: Verify CI is green on `main`**

Open the GitHub Actions tab. All `CI` jobs should be green.

- [ ] **Step 2: Tag the release**

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 3: Verify the release workflow**

Watch the `Release` workflow run. Steps to verify:
- Signing certificate imported
- `xcodebuild archive` succeeds
- Notarization completes (`Accepted` status)
- DMG built
- Release published with DMG attached
- `appcast.xml` updated on `main`
- Homebrew Cask bump PR opened

- [ ] **Step 4: Verify in-app update**

Install the published DMG. Re-run the workflow with a `v0.1.1` tag (after a minor fix or `--allow-empty` commit). The installed app should detect the update and offer to install it.

---

## Done When

- Tagging `v0.x.y` produces a signed, notarized DMG attached to a GitHub Release.
- `appcast.xml` on `main` lists every published version with EdDSA signatures.
- The installed app detects new releases via Sparkle and updates in place.
- `brew install --cask freedroid` works (after the first Homebrew Cask PR is merged).
- Weekly bot updates `adb` binary; monthly bot rebuilds libmtp xcframework.
- `THIRD_PARTY_NOTICES.md` is regenerated at every release and shipped inside the DMG via the app bundle.

## Self-Review

- Spec §11.3 (Distribution) → all channels covered (GH Releases, Homebrew, Sparkle).
- Spec §11.4 (Signing & notarization) → Tasks 5, 7.
- Spec §11.5 (Versioning) → SemVer + Conventional Commits + git-cliff + release-please (Task 1).
- Spec §11.1 (Licensing) → Task 2 (`THIRD_PARTY_NOTICES.md` generator).
- Spec §11.3 (Sparkle 2 EdDSA) → Tasks 3, 6, 7.
