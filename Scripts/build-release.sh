#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: build-release.sh <version>}"
BUILD_DIR="build/release"
APP_NAME="FreeDroid"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-freedroid-notary}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Substitute the Sparkle public key into Info.plist before archiving.
# The release workflow sets SPARKLE_PUBLIC_KEY from the stored keypair.
if [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" FreeDroid/Info.plist
fi

xcodebuild archive \
  -workspace FreeDroid.xcworkspace \
  -scheme FreeDroid \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM env var not set}" \
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
