#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="${1:?usage: package.sh <version>}"
IDENTITY="${SIGN_IDENTITY:--}"
if [ "${NOTARIZE:-0}" = "1" ] && [ "$IDENTITY" = "-" ]; then
  echo "NOTARIZE=1 requires a real SIGN_IDENTITY (Developer ID)"; exit 1
fi
ENT="App/ClaudeStatusBar.entitlements"
rm -rf build dist && mkdir -p dist
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
APP="build/Build/Products/Release/ClaudeStatusBar.app"
FW="$APP/Contents/Frameworks/Sparkle.framework"

# Drop Sparkle's Downloader XPC — the app has network.client, so it's unnecessary
# (and pulls in a deprecated WebView). Keep Installer.xpc for the sandboxed install.
rm -rf "$FW/Versions/B/XPCServices/Downloader.xpc"

# Timestamp only with a real identity (ad-hoc cannot timestamp).
if [ "$IDENTITY" = "-" ]; then TS=(); else TS=(--timestamp); fi
sign() { codesign -f -o runtime ${TS[@]+"${TS[@]}"} -s "$IDENTITY" "$@"; }

# Sign inside-out; app last with entitlements. NEVER --deep.
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
codesign -f -o runtime ${TS[@]+"${TS[@]}"} --entitlements "$ENT" -s "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# Notarize + staple the app BEFORE it's copied into the DMG, so the app a user
# drags out of the DMG carries the notarization ticket (not just the external
# $APP / the DMG itself). This is a separate submission from the DMG's below —
# two submissions total, intended.
if [ "${NOTARIZE:-0}" = "1" ]; then
  APPZIP="$(mktemp -d)/app.zip"
  ditto -c -k --keepParent "$APP" "$APPZIP"
  xcrun notarytool submit "$APPZIP" --key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" \
    --issuer "$AC_API_ISSUER_ID" --wait
  xcrun stapler staple "$APP"
fi

# DMG (volume icon + drag-to-Applications) — build from the signed (and, when
# notarized, already-stapled) app.
ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET_TMP"
for pair in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" \
            "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  cp "App/Assets.xcassets/AppIcon.appiconset/icon_${src}.png" "$ICONSET_TMP/icon_${dst}.png"
done
ICNS="$(mktemp -d)/AppIcon.icns"; iconutil -c icns "$ICONSET_TMP" -o "$ICNS"
DMG="dist/ClaudeStatusBar-$VERSION.dmg"
STAGE="$(mktemp -d)/dmg"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"
if command -v create-dmg >/dev/null 2>&1 && create-dmg \
      --volname "Claude Status Bar" --volicon "$ICNS" \
      --window-pos 200 120 --window-size 600 400 --icon-size 120 \
      --icon "ClaudeStatusBar.app" 150 200 --app-drop-link 450 200 \
      --hide-extension "ClaudeStatusBar.app" --no-internet-enable "$DMG" "$STAGE"; then
  echo "built $DMG via create-dmg"
else
  ln -sf /Applications "$STAGE/Applications"
  hdiutil create -volname "Claude Status Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi

# Code-sign the DMG itself (so `spctl -a -t open` verifies it via a primary signature, not
# only the stapled ticket), then notarize + staple. The app inside was already stapled above.
if [ "${NOTARIZE:-0}" = "1" ]; then
  codesign -f --timestamp -s "$IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" \
    --issuer "$AC_API_ISSUER_ID" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG" || true
  spctl -a -t exec -vv "$APP" || true
fi

# Sparkle update zip contains the (stapled, when notarized) app.
ZIP="dist/ClaudeStatusBar-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "$ZIP"; echo "$DMG"
