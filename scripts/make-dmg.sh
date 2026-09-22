#!/bin/bash
# Packages the signed app into a DMG for distribution.
#
# Usage:
#   VERSION="1.0.0" ./scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.1}"
APP="dist/SeratoLyrics.app"
DMG="dist/SeratoLyrics-$VERSION.dmg"
[ -d "$APP" ] || { echo "No $APP — run ./scripts/build-app.sh first"; exit 1; }

rm -f "$DMG"
hdiutil create -volname "SeratoLyrics" -srcfolder "$APP" -ov -format UDZO "$DMG"
echo "==> Done: $DMG"
