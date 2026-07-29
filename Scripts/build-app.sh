#!/usr/bin/env bash
#
# Builds ClaudeCompanion.app from the SwiftPM executable.
#
# SwiftPM produces a bare Mach-O; macOS needs a bundle for LSUIElement, the
# Keychain identity and login-item registration to work. This assembles one.
#
#   ./Scripts/build-app.sh [debug|release]     (default: release)

set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudeCompanion"
APP="${ROOT}/build/${APP_NAME}.app"

cd "$ROOT"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${APP}/Contents/Info.plist"

# SwiftPM emits one .bundle per dependency that ships resources (KeyboardShortcuts
# ships its localisations this way). Bundle.module resolves them from
# Contents/Resources at runtime.
shopt -s nullglob
for bundle in "${BIN_DIR}"/*.bundle; do
    cp -R "$bundle" "${APP}/Contents/Resources/"
done
shopt -u nullglob

printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Ad-hoc signature. Enough for local use; replace with a Developer ID identity
# to get a stable Keychain identity across builds and to distribute the app.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Done: ${APP}"
echo "    Launch with: open \"${APP}\""
