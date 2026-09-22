#!/bin/bash
# Notarizes and staples a LiveLyricDJ app and its DMG with Apple's notary service.
# Requires a Developer ID Application certificate and App Store Connect
# credentials. Use a keychain profile to avoid passing secrets on the CLI:
#
#   xcrun notarytool store-credentials "SeratoLyrics" \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Usage:
#   VERSION="1.0.3" ./scripts/notarize.sh # uses keychain profile "SeratoLyrics"
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/LiveLyricDJ.app"
[ -d "$APP" ] || { echo "No $APP — run ./scripts/build-app.sh with SIGN_IDENTITY first"; exit 1; }
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
ZIP="dist/LiveLyricDJ-$VERSION-notarization.zip"
DMG="dist/LiveLyricDJ-$VERSION.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -n 1)}"
[ -n "$SIGN_IDENTITY" ] || { echo "No Developer ID Application signing identity found on $APP"; exit 1; }

echo "==> Archiving app for notarization"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$ZIP" --wait \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APPLE_APP_PASSWORD"
else
    xcrun notarytool submit "$ZIP" --wait --keychain-profile "SeratoLyrics"
fi

xcrun stapler staple "$APP"
SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" ./scripts/make-dmg.sh

if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$DMG" --wait \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APPLE_APP_PASSWORD"
else
    xcrun notarytool submit "$DMG" --wait --keychain-profile "SeratoLyrics"
fi

xcrun stapler staple "$DMG"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl -a -vv "$APP"
spctl -a -vv --type open --context context:primary-signature "$DMG"
echo "==> Notarized, stapled release: $DMG"
