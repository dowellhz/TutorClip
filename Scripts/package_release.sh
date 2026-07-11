#!/bin/sh
set -eu

APP_PATH=${1:?app path required}
DMG_PATH=${2:?dmg path required}
SIGNING_IDENTITY=${3:?signing identity required}
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tutorclip-dmg.XXXXXX")

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"
codesign --verify --deep --strict "$APP_PATH"
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")
APP_BUILD=$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")
ditto "$APP_PATH" "$STAGING_DIR/TutorClip.app"
codesign --verify --deep --strict "$STAGING_DIR/TutorClip.app"
./Scripts/build_installer.sh \
    "$STAGING_DIR/Install TutorClip.app" \
    "$APP_PATH/Contents/Resources/AppIcon.icns" \
    "$SIGNING_IDENTITY" \
    "$APP_VERSION" \
    "$APP_BUILD"
codesign --verify --deep --strict "$STAGING_DIR/Install TutorClip.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "TutorClip" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
echo "Created signed installer: $DMG_PATH"
