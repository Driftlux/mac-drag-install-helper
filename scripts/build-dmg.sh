#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DISPLAY_NAME="DMG安装器"
VERSION="0.3.1"
VOLUME_NAME="DMG安装器"
APP_PATH="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
STAGING_DIR="$ROOT_DIR/dist/dmg-root"
BACKGROUND_PATH="$ROOT_DIR/dist/dmg-background.png"
RW_DMG="$ROOT_DIR/dist/$APP_DISPLAY_NAME-v$VERSION-rw.dmg"
FINAL_DMG="$ROOT_DIR/dist/DMG-Installer-v$VERSION.dmg"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGING_DIR" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$STAGING_DIR/.background"
ditto "$APP_PATH" "$STAGING_DIR/$APP_DISPLAY_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
swift "$ROOT_DIR/scripts/generate-dmg-background.swift" "$BACKGROUND_PATH"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/background.png"

hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -format UDRW "$RW_DMG"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 880, 580}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 104
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "$APP_DISPLAY_NAME.app" of container window to {220, 230}
    set position of item "Applications" of container window to {540, 230}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$RW_DMG"

echo "Built $FINAL_DMG"
