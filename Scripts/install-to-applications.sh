#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${PRODUCT_NAME:-FreeDroid}"
APP_BUNDLE="${APP_NAME}.app"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-}"
DEST="/Applications/${APP_BUNDLE}"
APPEX_BUNDLE_ID="com.merkost.freedroid.FreeDroidFS"

if [ -z "$BUILT_PRODUCTS_DIR" ]; then
    BUILT_PRODUCTS_DIR="$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 6 -name "${APP_BUNDLE}" -path '*/Debug/*' -print -quit)"
    BUILT_PRODUCTS_DIR="$(dirname "$BUILT_PRODUCTS_DIR")"
fi

SOURCE="${BUILT_PRODUCTS_DIR}/${APP_BUNDLE}"

if [ ! -d "$SOURCE" ]; then
    echo "Source app not found at $SOURCE"
    exit 1
fi

osascript -e 'tell application "FreeDroid" to quit' >/dev/null 2>&1 || true
sleep 1

rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"

LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister"

if [ -d "$DEST/Contents/Extensions/FreeDroidFS.appex" ]; then
    while IFS= read -r stale; do
        case "$stale" in
            "$DEST/Contents/Extensions/FreeDroidFS.appex") continue ;;
            /System/*) continue ;;
        esac
        pluginkit -r "$stale" 2>/dev/null || true
    done < <(find ~/Library/Developer/Xcode/DerivedData -name 'FreeDroidFS.appex' -type d 2>/dev/null)

    while IFS= read -r staleApp; do
        case "$staleApp" in
            /Applications/*) continue ;;
        esac
        "$LSREG" -u "$staleApp" 2>/dev/null || true
    done < <(find ~/Library/Developer/Xcode/DerivedData -name 'FreeDroid.app' -type d 2>/dev/null)

    find ~/Library/Developer/Xcode/DerivedData -name 'FreeDroidFS.appex' -type d \
        ! -path "$DEST/*" -exec rm -rf {} + 2>/dev/null || true

    pluginkit -a "$DEST/Contents/Extensions/FreeDroidFS.appex" 2>/dev/null || true
    "$LSREG" "$DEST" 2>/dev/null || true
    sleep 1
    pluginkit -e use -p com.apple.fskit.fsmodule -i "$APPEX_BUNDLE_ID" 2>/dev/null || true
fi

echo "Installed at $DEST"
