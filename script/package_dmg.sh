#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
STAGING_DIR="$ROOT_DIR/.build/dmg"
DMG_PATH="$ROOT_DIR/outputs/$APP_NAME.dmg"

BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --build-only
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$ROOT_DIR/outputs"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
