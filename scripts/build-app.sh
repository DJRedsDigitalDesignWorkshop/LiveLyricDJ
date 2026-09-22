#!/bin/bash
# Builds SeratoLyrics.app from the SwiftPM release binary.
#
# Usage:
#   ./scripts/build-app.sh                          # ad-hoc signed (local testing)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/build-app.sh
#   BUNDLE_ID="com.example.seratolyrics" VERSION="1.0.1" ./scripts/build-app.sh
#   INSTALL_APPS=0 ./scripts/build-app.sh           # skip install to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SeratoLyrics"
BUNDLE_ID="${BUNDLE_ID:-com.seratolyrics.app}"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
INSTALL_APPS="${INSTALL_APPS:-1}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

echo "==> Assembling $APP_NAME.app"
APP="dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

echo "==> Signing"
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        --identifier "$BUNDLE_ID" "$APP"
    echo "    signed with: $SIGN_IDENTITY (hardened runtime)"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "    ad-hoc signed (local testing only)"
fi

codesign --verify --deep --strict "$APP" && echo "    codesign verify: OK"

echo "==> Installing to /Applications"
if [ "$INSTALL_APPS" = "1" ]; then
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo "    quitting running instance"
        pkill -x "$APP_NAME" || true
        sleep 1
    fi
    cp -R "$APP" /Applications/
    echo "    installed: /Applications/$APP_NAME.app"
else
    echo "    skipped (INSTALL_APPS=0)"
fi

echo "==> Done: $APP"
echo "    Bundle ID: $BUNDLE_ID  Version: $VERSION"