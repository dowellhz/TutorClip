#!/bin/sh
set -eu

OUTPUT_APP=${1:?output app required}
ICON_PATH=${2:?icon path required}
SIGNING_IDENTITY=${3:?signing identity required}
APP_VERSION=${4:?app version required}
APP_BUILD=${5:?app build required}
SOURCE="Sources/TutorClipInstaller/main.swift"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tutorclip-installer.XXXXXX")

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

rm -rf "$OUTPUT_APP"
mkdir -p "$OUTPUT_APP/Contents/MacOS" "$OUTPUT_APP/Contents/Resources"

xcrun swiftc -parse-as-library -O -module-cache-path "$WORK_DIR/module-cache-arm64" -target arm64-apple-macos26.0 -framework AppKit -framework Security "$SOURCE" -o "$WORK_DIR/installer-arm64"
xcrun swiftc -parse-as-library -O -module-cache-path "$WORK_DIR/module-cache-x86_64" -target x86_64-apple-macos26.0 -framework AppKit -framework Security "$SOURCE" -o "$WORK_DIR/installer-x86_64"
lipo -create "$WORK_DIR/installer-arm64" "$WORK_DIR/installer-x86_64" -output "$OUTPUT_APP/Contents/MacOS/TutorClip Installer"
cp "$ICON_PATH" "$OUTPUT_APP/Contents/Resources/AppIcon.icns"

plutil -create xml1 "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string en "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "TutorClip Installer" "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "TutorClip Installer" "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleIconFile -string AppIcon "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.linlu.TutorClip.Installer "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleName -string "TutorClip Installer" "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$OUTPUT_APP/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$APP_BUILD" "$OUTPUT_APP/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 26.0 "$OUTPUT_APP/Contents/Info.plist"

codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$OUTPUT_APP"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
