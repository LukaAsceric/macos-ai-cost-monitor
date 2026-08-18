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
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_BIN="${SPARKLE_BIN:-}"
RELEASE_DOWNLOAD_BASE_URL="${RELEASE_DOWNLOAD_BASE_URL:-}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"

rm -rf "$DIST_DIR" "$SCRATCH_ROOT"
mkdir -p "$DIST_DIR" "$SCRATCH_ROOT"

swift test

build_architecture() {
    local architecture="$1"
    local scratch_path="$SCRATCH_ROOT/$architecture"
    local bin_path

    swift build -c release --arch "$architecture" --scratch-path "$scratch_path"
    bin_path="$(swift build -c release --arch "$architecture" --scratch-path "$scratch_path" --show-bin-path)"
    test -x "$bin_path/$APP_NAME"
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

if ! otool -L "$APP_DIR/Contents/MacOS/$APP_NAME" | grep -q 'Sparkle.framework/Versions'; then
    echo "The executable is not linked against Sparkle.framework" >&2
    exit 1
fi

SPARKLE_XCFRAMEWORK="$(find "$ROOT_DIR/.build" -type d -path '*/Sparkle.xcframework' -print -quit)"
if [[ -z "$SPARKLE_XCFRAMEWORK" ]]; then
    echo "Sparkle.xcframework was not found in the SwiftPM build artifacts" >&2
    exit 1
fi

SPARKLE_FRAMEWORK="$SPARKLE_XCFRAMEWORK/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Universal Sparkle.framework slice was not found" >&2
    exit 1
fi

mkdir -p "$APP_DIR/Contents/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP_DIR/Contents/MacOS/$APP_NAME" | grep -q '@loader_path/../Frameworks'; then
    install_name_tool -add_rpath '@loader_path/../Frameworks' "$APP_DIR/Contents/MacOS/$APP_NAME"
fi

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif command -v iconutil >/dev/null 2>&1 && [[ -d "Resources/AppIcon.iconset" ]]; then
    iconutil -c icns "Resources/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
fi

SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR/Contents/MacOS/$APP_NAME"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR"
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

The app requires macOS 13 or later and an OpenRouter management key. Packaged releases use Sparkle for signed updates.
NOTE

DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS.dmg"
hdiutil create \
    -volname "$DISPLAY_NAME $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"
rm -f "$DIST_DIR/SHA256SUMS.txt" "$DIST_DIR/appcast.xml"
(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > SHA256SUMS.txt
)

if [[ -n "$SPARKLE_BIN" && -n "$RELEASE_DOWNLOAD_BASE_URL" ]]; then
    if [[ -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
        echo "SPARKLE_EDDSA_PRIVATE_KEY is required to publish a signed Sparkle appcast" >&2
        exit 1
    fi

    UPDATE_INPUT_DIR="$DIST_DIR/update-input"
    mkdir -p "$UPDATE_INPUT_DIR"
    cp "$ZIP_PATH" "$UPDATE_INPUT_DIR/"
    UPDATE_NOTES_NAME="${APP_NAME}-${VERSION}-macOS.md"
    if [[ -n "$RELEASE_NOTES_FILE" ]]; then
        test -f "$RELEASE_NOTES_FILE"
        cp "$RELEASE_NOTES_FILE" "$UPDATE_INPUT_DIR/$UPDATE_NOTES_NAME"
    else
        cat > "$UPDATE_INPUT_DIR/$UPDATE_NOTES_NAME" <<NOTE
## What's new

See the release description for the release notes.

Installation instructions are maintained in the repository README:
https://github.com/LukaAsceric/macos-ai-cost-monitor#install-a-release
NOTE
    fi

    printf '%s\n' "$SPARKLE_EDDSA_PRIVATE_KEY" | \
        "$SPARKLE_BIN/generate_appcast" \
            --ed-key-file - \
            --download-url-prefix "${RELEASE_DOWNLOAD_BASE_URL%/}/" \
            --release-notes-url-prefix "${RELEASE_DOWNLOAD_BASE_URL%/}/" \
            --embed-release-notes \
            "$UPDATE_INPUT_DIR"

    cp "$UPDATE_INPUT_DIR/appcast.xml" "$DIST_DIR/appcast.xml"
    cp "$UPDATE_INPUT_DIR/$UPDATE_NOTES_NAME" "$DIST_DIR/$UPDATE_NOTES_NAME"
    rm -rf "$UPDATE_INPUT_DIR"
else
    echo "Sparkle appcast generation is disabled: signing tools or release URL are not configured."
fi

printf 'Created release artifacts:\n'
file "$APP_DIR/Contents/MacOS/$APP_NAME" "$DMG_PATH" "$ZIP_PATH"
printf '\nSHA-256:\n'
cat "$DIST_DIR/SHA256SUMS.txt"
printf '\nApp bundle: %s\n' "$APP_DIR"
