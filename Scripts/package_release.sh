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
ditto "$APP_PATH" "$STAGING_DIR/TutorClip.app"
codesign --verify --deep --strict "$STAGING_DIR/TutorClip.app"
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
