#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

APP_DIR="$ROOT_DIR/dist/MacOSAICostMonitor.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/release/MacOSAICostMonitor" "$APP_DIR/Contents/MacOS/MacOSAICostMonitor"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if command -v codesign >/dev/null 2>&1; then
  SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
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
  - Sparkle / auto-update
  - Mac App Store packaging and sandbox entitlements
  - OpenRouter OAuth login (analytics requires a management key)
NOTE

printf '%s\n' "$APP_DIR"
