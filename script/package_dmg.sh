#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
STAGING_DIR="$ROOT_DIR/.build/dmg"
DMG_PATH="$ROOT_DIR/outputs/$APP_NAME.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

BUILD_CONFIGURATION=release UNIVERSAL="${UNIVERSAL:-1}" \
  SIGN_IDENTITY="$SIGN_IDENTITY" \
  "$ROOT_DIR/script/build_and_run.sh" --build-only
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

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY" >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
