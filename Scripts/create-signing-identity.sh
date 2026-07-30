#!/usr/bin/env bash
#
# Creates a stable, self-signed code-signing identity in your login keychain.
#
# Why this exists: macOS ties Screen Recording, Camera and Microphone
# permissions to an app's code signature. An ad-hoc signature ("-") is
# different on every build, so each rebuild looks like a brand-new app and the
# permissions you granted stop applying. A stable identity fixes that — grant
# once, and it holds across rebuilds.
#
# Run once:
#
#   ./Scripts/create-signing-identity.sh
#
# Then build as usual; build-app.sh picks the identity up automatically.
#
# To undo: open Keychain Access, search for the name below, delete it.

set -euo pipefail

IDENTITY_NAME="${1:-Claude Pet}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    echo "==> \"$IDENTITY_NAME\" already exists — nothing to do."
    echo "    Build with: ./Scripts/build-app.sh"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Creating a self-signed code-signing certificate: $IDENTITY_NAME"

# codeSigning EKU is what makes codesign accept it; CA:false keeps it a leaf.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=${IDENTITY_NAME}" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "keyUsage=critical,digitalSignature" 2>/dev/null

openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY_NAME" -passout pass: 2>/dev/null

echo "==> Importing into the login keychain"
echo "    macOS may ask for your login password — that is the keychain unlock."
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# Without this, codesign prompts for keychain access on every single build.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || \
    echo "    (Skipped the partition-list step — codesign may prompt once per build.)"

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "==> Done. \"$IDENTITY_NAME\" is now a signing identity."
    echo
    echo "Next:"
    echo "  1. ./Scripts/build-app.sh          # signs with it automatically"
    echo "  2. Open the app, grant Screen Recording when asked"
    echo "  3. The grant now survives rebuilds"
else
    echo "!! The identity was not created. Falling back to ad-hoc signing." >&2
    exit 1
fi
