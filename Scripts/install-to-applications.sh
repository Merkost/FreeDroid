#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${PRODUCT_NAME:-FreeDroid}"
APP_BUNDLE="${APP_NAME}.app"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-}"
DEST="/Applications/${APP_BUNDLE}"

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
"$LSREG" "$DEST" 2>/dev/null || true

echo "Installed at $DEST"
