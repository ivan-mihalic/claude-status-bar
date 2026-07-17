#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="${1:?usage: package.sh <version>}"
rm -rf build dist && mkdir -p dist
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
APP="build/Build/Products/Release/ClaudeStatusBar.app"
# Ad-hoc sign the whole bundle (incl. the embedded Sparkle framework/XPC services).
# Sparkle's generate_appcast rejects fully-unsigned apps ("failed Apple Code Signing
# checks"), so a signature is required even though updates are authenticated by the
# EdDSA SUPublicEDKey (not by Apple code signing / notarization). We deliberately do
# NOT notarize — see docs (Gatekeeper section) for the one-time first-launch bypass.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# --- ZIP (Sparkle auto-update enclosure; hosted on Pages) ---------------------
# ditto preserves the symlinks/permissions Sparkle needs.
ZIP="dist/ClaudeStatusBar-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# --- DMG (pretty manual download from the Releases page) ----------------------
# Volume icon (.icns) built from the same app-icon asset PNGs.
ICONSET_SRC="App/Assets.xcassets/AppIcon.appiconset"
ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET_TMP"
cp "$ICONSET_SRC/icon_16.png"   "$ICONSET_TMP/icon_16x16.png"
cp "$ICONSET_SRC/icon_32.png"   "$ICONSET_TMP/icon_16x16@2x.png"
cp "$ICONSET_SRC/icon_32.png"   "$ICONSET_TMP/icon_32x32.png"
cp "$ICONSET_SRC/icon_64.png"   "$ICONSET_TMP/icon_32x32@2x.png"
cp "$ICONSET_SRC/icon_128.png"  "$ICONSET_TMP/icon_128x128.png"
cp "$ICONSET_SRC/icon_256.png"  "$ICONSET_TMP/icon_128x128@2x.png"
cp "$ICONSET_SRC/icon_256.png"  "$ICONSET_TMP/icon_256x256.png"
cp "$ICONSET_SRC/icon_512.png"  "$ICONSET_TMP/icon_256x256@2x.png"
cp "$ICONSET_SRC/icon_512.png"  "$ICONSET_TMP/icon_512x512.png"
cp "$ICONSET_SRC/icon_1024.png" "$ICONSET_TMP/icon_512x512@2x.png"
ICNS="$(mktemp -d)/AppIcon.icns"
iconutil -c icns "$ICONSET_TMP" -o "$ICNS"

DMG="dist/ClaudeStatusBar-$VERSION.dmg"
STAGE="$(mktemp -d)/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# create-dmg gives a Finder-laid-out window (app on the left, drag-to-Applications
# on the right, volume icon). It uses AppleScript, which needs a logged-in GUI
# session — fine on the GitHub macOS runners. Fall back to a plain hdiutil DMG
# (app + Applications symlink, no custom layout) if create-dmg is missing or fails,
# so a release never breaks on the packaging step.
if command -v create-dmg >/dev/null 2>&1 && create-dmg \
      --volname "Claude Status Bar" \
      --volicon "$ICNS" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 120 \
      --icon "ClaudeStatusBar.app" 150 200 \
      --app-drop-link 450 200 \
      --hide-extension "ClaudeStatusBar.app" \
      --no-internet-enable \
      "$DMG" "$STAGE"; then
  echo "built $DMG via create-dmg"
else
  echo "create-dmg unavailable or failed — building plain DMG via hdiutil"
  ln -sf /Applications "$STAGE/Applications"
  hdiutil create -volname "Claude Status Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi

echo "$ZIP"
echo "$DMG"
