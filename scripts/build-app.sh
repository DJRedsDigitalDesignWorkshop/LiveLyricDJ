#!/bin/bash
# Builds SeratoLyrics.app from the SwiftPM release binary.
#
# Usage:
#   ./scripts/build-app.sh                          # ad-hoc signed (local testing)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/build-app.sh
#   BUNDLE_ID="com.example.seratolyrics" VERSION="1.0.2" ./scripts/build-app.sh
#   INSTALL_APPS=0 ./scripts/build-app.sh           # skip install to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SeratoLyrics"
BUNDLE_ID="${BUNDLE_ID:-com.seratolyrics.app}"
VERSION="${VERSION:-1.0.2}"
BUILD="${BUILD:-3}"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
INSTALL_APPS="${INSTALL_APPS:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
BUILD_DIR=".build/seratolyrics-universal"

case "$CONFIG" in
    release) CONFIG_DIR="Release" ;;
    debug) CONFIG_DIR="Debug" ;;
    *) echo "Unsupported CONFIG: $CONFIG"; exit 1 ;;
esac

echo "==> Building ($CONFIG) for $ARCHS"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
for ARCH in $ARCHS; do
    swift build -c "$CONFIG" --triple "$ARCH-apple-macosx13.0"
    cp ".build/out/Products/$CONFIG_DIR/$APP_NAME" "$BUILD_DIR/$APP_NAME-$ARCH"
    # Swift may linker-sign one architecture but not the other. Strip any
    # build-time signature before lipo creates the universal executable.
    codesign --remove-signature "$BUILD_DIR/$APP_NAME-$ARCH" 2>/dev/null || true
done

echo "==> Assembling $APP_NAME.app"
APP="dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$(echo "$ARCHS" | wc -w | tr -d ' ')" = "1" ]; then
    cp "$BUILD_DIR/$APP_NAME-$ARCHS" "$APP/Contents/MacOS/$APP_NAME"
else
    lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" \
        -output "$APP/Contents/MacOS/$APP_NAME"
fi
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
