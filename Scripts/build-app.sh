#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

APP_DIR="$ROOT_DIR/dist/MacOSAICostMonitor.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp ".build/release/MacOSAICostMonitor" "$APP_DIR/Contents/MacOS/MacOSAICostMonitor"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
fi

if ! otool -L "$APP_DIR/Contents/MacOS/MacOSAICostMonitor" | grep -q 'Sparkle.framework/Versions'; then
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
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"

if ! otool -l "$APP_DIR/Contents/MacOS/MacOSAICostMonitor" | grep -q '@loader_path/../Frameworks'; then
  install_name_tool -add_rpath '@loader_path/../Frameworks' "$APP_DIR/Contents/MacOS/MacOSAICostMonitor"
fi

if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if command -v codesign >/dev/null 2>&1; then
  SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR/Contents/MacOS/MacOSAICostMonitor"
  codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
fi

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP_DIR/Contents/Info.plist"
fi

cat <<'NOTE'
Local release bundle created.

Supported here:
  - unsigned or ad-hoc / Apple Development codesign
  - codesign --verify --deep --strict
  - plutil -lint

Not included in this app:
  - Developer ID notarization (use notarytool separately)
  - Mac App Store packaging and sandbox entitlements
  - OpenRouter OAuth login (analytics requires a management key)
NOTE

printf '%s\n' "$APP_DIR"
