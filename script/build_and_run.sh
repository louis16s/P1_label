#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="P1Label"
BUNDLE_ID="com.louis.p1label"
MIN_SYSTEM_VERSION="26.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/P1Label/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>P1 Label</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 louis16s</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>用于搜索并连接德佟 P1 蓝牙打印机。</string>
  <key>NSBluetoothPeripheralUsageDescription</key><string>用于搜索并连接德佟 P1 蓝牙打印机。</string>
</dict></plist>
PLIST

SIGNING_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | /usr/bin/head -n 1)"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  # Development builds currently load Homebrew's libusb from /opt/homebrew.
  # Keep a stable Apple Development identity for TCC permissions, but defer
  # hardened runtime until libusb is bundled and signed inside the app.
  /usr/bin/codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" --entitlements "$ROOT_DIR/P1Label.entitlements" "$APP_BUNDLE"
else
  /usr/bin/codesign --force --sign - --entitlements "$ROOT_DIR/P1Label.entitlements" "$APP_BUNDLE"
fi

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }

case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
