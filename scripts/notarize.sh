#!/bin/bash
# Notarizes and staples SeratoLyrics.app with Apple's notary service.
# Requires a Developer ID Application certificate and App Store Connect
# credentials. Use a keychain profile to avoid passing secrets on the CLI:
#
#   xcrun notarytool store-credentials "SeratoLyrics" \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Usage:
#   ./scripts/notarize.sh                 # uses keychain profile "SeratoLyrics"
#   APPLE_ID=... TEAM_ID=... APPLE_APP_PASSWORD=... ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/SeratoLyrics.app"
[ -d "$APP" ] || { echo "No $APP — run ./scripts/build-app.sh with SIGN_IDENTITY first"; exit 1; }

if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$APP" --wait \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APPLE_APP_PASSWORD"
else
    xcrun notarytool submit "$APP" --wait --keychain-profile "SeratoLyrics"
fi

xcrun stapler staple "$APP"
echo "==> Notarized and stapled: $APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier" || true