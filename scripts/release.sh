#!/bin/bash
# Build, sign, and (optionally) notarize a distributable swiftborders binary.
#
# One-time setup for notarization (needs an app-specific password from
# https://account.apple.com → Sign-In and Security → App-Specific Passwords):
#   xcrun notarytool store-credentials swiftborders \
#     --apple-id you@example.com --team-id YVZG5QKT42
#
# Usage:
#   scripts/release.sh            # build + sign
#   scripts/release.sh notarize   # build + sign + notarize the zip
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: Alberto Benatti (YVZG5QKT42)"
BUNDLE_ID="it.albibenni.swiftborders"
KEYCHAIN_PROFILE="swiftborders"
DIST=dist

swift build -c release --arch arm64 --arch x86_64
BINARY=.build/apple/Products/Release/swiftborders

mkdir -p "$DIST"
cp "$BINARY" "$DIST/swiftborders"

# Hardened runtime + secure timestamp are required for notarization. The
# stable identifier keeps the Accessibility (TCC) grant across updates.
codesign --force --sign "$IDENTITY" \
  --identifier "$BUNDLE_ID" \
  --options runtime \
  --timestamp \
  "$DIST/swiftborders"

codesign --verify --strict --verbose=2 "$DIST/swiftborders"
echo "signed: $DIST/swiftborders"

if [[ "${1:-}" == "notarize" ]]; then
  ditto -c -k "$DIST/swiftborders" "$DIST/swiftborders.zip"
  xcrun notarytool submit "$DIST/swiftborders.zip" \
    --keychain-profile "$KEYCHAIN_PROFILE" --wait
  # Bare executables can't be stapled; Gatekeeper verifies notarization
  # online from the signature. Ship the zip.
  echo "notarized: $DIST/swiftborders.zip"
fi
