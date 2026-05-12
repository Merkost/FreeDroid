#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

cd "$REPO_ROOT"

xcodegen generate --spec project.yml

python3 "$SCRIPT_DIR/patch-pbxproj-local-packages.py"

echo "Project generated and patched for Xcode 26 local-package compatibility."
