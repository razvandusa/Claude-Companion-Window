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
# The product (binary and SwiftPM target) keeps its original name; only the
# bundle the user sees is "Claude Pet".
PRODUCT_NAME="ClaudeCompanion"
APP_NAME="Claude Pet"
APP="${ROOT}/build/${APP_NAME}.app"

cd "$ROOT"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_DIR}/${PRODUCT_NAME}" "${APP}/Contents/MacOS/${PRODUCT_NAME}"
cp "${ROOT}/Resources/Info.plist" "${APP}/Contents/Info.plist"
cp "${ROOT}/Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

# SwiftPM emits one .bundle per dependency that ships resources (KeyboardShortcuts
# ships its localisations this way). Bundle.module resolves them from
# Contents/Resources at runtime.
shopt -s nullglob
for bundle in "${BIN_DIR}"/*.bundle; do
    cp -R "$bundle" "${APP}/Contents/Resources/"
done
shopt -u nullglob

printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Signing identity.
#
# An ad-hoc signature ("-") changes on every build, and macOS keys Screen
# Recording, Camera and Microphone permissions to the signature. So each
# rebuild looks like a brand-new app: the permission you granted no longer
# applies, the system asks again, and captures fail until you re-grant it.
#
# Set CODESIGN_IDENTITY to a stable identity to keep permissions across builds:
#
#   1. Keychain Access → Certificate Assistant → Create a Certificate…
#      name it e.g. "Claude Companion", type "Code Signing", self-signed.
#   2. export CODESIGN_IDENTITY="Claude Companion"
#
# A Developer ID identity works the same way and is what you'd use to ship.
IDENTITY="${CODESIGN_IDENTITY:--}"

if [ "$IDENTITY" = "-" ]; then
    echo "==> Signing (ad-hoc — permissions will be re-requested after each build)"
else
    echo "==> Signing as ${IDENTITY}"
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"

echo "==> Done: ${APP}"
echo "    Launch with: open \"${APP}\""
