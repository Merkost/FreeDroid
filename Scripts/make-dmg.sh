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
