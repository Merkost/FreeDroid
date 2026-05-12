#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: sparkle-sign.sh <version> <dmg> <release-notes-url>}"
DMG_PATH="${2:?}"
NOTES_URL="${3:?}"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY_PATH:?SPARKLE_PRIVATE_KEY_PATH not set}"

# Locate sign_update from SPM-fetched Sparkle artifacts
DERIVED_DATA_DIR="${HOME}/Library/Developer/Xcode/DerivedData"
SIGN_TOOL="$(find "$DERIVED_DATA_DIR" -name "sign_update" -type f -perm -u+x 2>/dev/null | head -n 1)"

# Fall back to a local build if not found in DerivedData
if [ -z "$SIGN_TOOL" ]; then
  SPARKLE_CHECKOUT="$(find "$DERIVED_DATA_DIR" -path "*/checkouts/Sparkle" -type d 2>/dev/null | head -n 1)"
  if [ -n "$SPARKLE_CHECKOUT" ]; then
    xcodebuild -project "$SPARKLE_CHECKOUT/Sparkle.xcodeproj" \
      -scheme sign_update \
      -configuration Release \
      -derivedDataPath /tmp/sparkle-build \
      CODE_SIGNING_ALLOWED=NO \
      build 2>/dev/null
    SIGN_TOOL="/tmp/sparkle-build/Build/Products/Release/sign_update"
  fi
fi

if [ -z "$SIGN_TOOL" ] || [ ! -x "$SIGN_TOOL" ]; then
  echo "ERROR: Could not find or build sign_update. Ensure Sparkle is resolved via SPM." >&2
  exit 1
fi

SIGNATURE_OUT=$("$SIGN_TOOL" "$DMG_PATH" --ed-key-file "$PRIVATE_KEY")
DMG_SIZE=$(stat -f%z "$DMG_PATH")

cat <<EOF
<item>
  <title>FreeDroid $VERSION</title>
  <link>$NOTES_URL</link>
  <sparkle:version>$VERSION</sparkle:version>
  <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>15.4</sparkle:minimumSystemVersion>
  <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S GMT")</pubDate>
  <enclosure
    url="https://github.com/${GITHUB_REPOSITORY:-your-org/FreeDroid}/releases/download/v$VERSION/FreeDroid-$VERSION.dmg"
    sparkle:edSignature="$SIGNATURE_OUT"
    length="$DMG_SIZE"
    type="application/octet-stream" />
</item>
EOF
