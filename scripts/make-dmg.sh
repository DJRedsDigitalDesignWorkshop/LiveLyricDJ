#!/bin/bash
# Packages the signed app into a DMG for distribution.
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" VERSION="1.0.6" ./scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.6}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
APP="dist/LiveLyricDJ.app"
DMG="dist/LiveLyricDJ-$VERSION.dmg"
STAGING="dist/.dmg-staging"
[ -d "$APP" ] || { echo "No $APP — run ./scripts/build-app.sh first"; exit 1; }

rm -f "$DMG"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/LiveLyricDJ.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "LiveLyricDJ" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    echo "==> Signed disk image with: $SIGN_IDENTITY"
fi
echo "==> Done: $DMG"
