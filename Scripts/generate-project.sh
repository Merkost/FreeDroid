#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

cd "$REPO_ROOT"

LOCAL_CONFIG="Configs/Local.xcconfig"
EXAMPLE_CONFIG="Configs/Local.xcconfig.example"

if [ ! -f "$LOCAL_CONFIG" ]; then
    cp "$EXAMPLE_CONFIG" "$LOCAL_CONFIG"
    echo "==> Created $LOCAL_CONFIG from template."
    echo "    Edit it to set DEVELOPMENT_TEAM to your Apple Developer Team ID."
    echo "    Find your Team ID at https://developer.apple.com/account → Membership."
fi

xcodegen generate --spec project.yml

python3 "$SCRIPT_DIR/patch-pbxproj-local-packages.py"

echo "Project generated and patched for Xcode 26 local-package compatibility."
