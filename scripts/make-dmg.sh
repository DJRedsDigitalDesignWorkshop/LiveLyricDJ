#!/bin/bash
# Packages the signed app into a DMG for distribution.
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" VERSION="1.0.2" ./scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.2}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
APP="dist/SeratoLyrics.app"
DMG="dist/SeratoLyrics-$VERSION.dmg"
[ -d "$APP" ] || { echo "No $APP — run ./scripts/build-app.sh first"; exit 1; }

rm -f "$DMG"
hdiutil create -volname "SeratoLyrics" -srcfolder "$APP" -ov -format UDZO "$DMG"
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    echo "==> Signed disk image with: $SIGN_IDENTITY"
fi
echo "==> Done: $DMG"
