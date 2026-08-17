#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${VERSION:?Set VERSION, for example VERSION=0.1.0}"
APP_NAME="MacOSAICostMonitor"
DISPLAY_NAME="AI Cost Monitor"
DIST_DIR="$ROOT_DIR/dist"
SCRATCH_ROOT="$ROOT_DIR/.build/release-architectures"
APP_DIR="$DIST_DIR/$APP_NAME.app"

rm -rf "$DIST_DIR" "$SCRATCH_ROOT"
mkdir -p "$DIST_DIR" "$SCRATCH_ROOT"

swift test

build_architecture() {
    local architecture="$1"
    local scratch_path="$SCRATCH_ROOT/$architecture"
    local bin_path

    bin_path="$(swift build -c release --arch "$architecture" --scratch-path "$scratch_path" --show-bin-path)"
    cp "$bin_path/$APP_NAME" "$DIST_DIR/$APP_NAME-$architecture"
}

build_architecture arm64
build_architecture x86_64

lipo -create \
    "$DIST_DIR/$APP_NAME-arm64" \
    "$DIST_DIR/$APP_NAME-x86_64" \
    -output "$DIST_DIR/$APP_NAME-universal"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$DIST_DIR/$APP_NAME-universal" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"

SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$DIST_DIR/$APP_NAME-arm64" "$DIST_DIR/$APP_NAME-x86_64" "$DIST_DIR/$APP_NAME-universal"

ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

DMG_STAGING="$DIST_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

cat > "$DMG_STAGING/README.txt" <<NOTE
$DISPLAY_NAME $VERSION

Drag $APP_NAME.app to Applications.

This preview is ad-hoc signed. On first launch, macOS may require:
1. Control-click the app and choose Open, or
2. Open System Settings > Privacy & Security and choose Open Anyway.

The app requires macOS 13 or later and an OpenRouter management key.
NOTE

DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS.dmg"
hdiutil create \
    -volname "$DISPLAY_NAME $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"
rm -f "$DIST_DIR/SHA256SUMS.txt" "$DIST_DIR/RELEASE_NOTES.md"
(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > SHA256SUMS.txt
)

cat > "$DIST_DIR/RELEASE_NOTES.md" <<NOTE
## Install

1. Download **$APP_NAME-$VERSION-macOS.dmg**.
2. Open the disk image and drag **$APP_NAME.app** to **Applications**.
3. On first launch, macOS may show an unidentified-developer warning because this preview is ad-hoc signed. Control-click the app, choose **Open**, and confirm. If needed, use **System Settings → Privacy & Security → Open Anyway**.
4. Open Settings → Provider and add an OpenRouter management key.

The ZIP contains the same universal app. `SHA256SUMS.txt` contains SHA-256 checksums for both installers.

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac
- OpenRouter management key with analytics access

## Security

The management key is stored in macOS Keychain. It is not included in the app, DMG, ZIP, logs, cache, or release artifacts.

## Distribution note

This is an unsigned/notarization-free public preview. A future Developer ID + notarized release will remove the first-launch Gatekeeper step.
NOTE

printf 'Created release artifacts:\n'
file "$APP_DIR/Contents/MacOS/$APP_NAME" "$DMG_PATH" "$ZIP_PATH"
printf '\nSHA-256:\n'
cat "$DIST_DIR/SHA256SUMS.txt"
printf '\nApp bundle: %s\n' "$APP_DIR"
