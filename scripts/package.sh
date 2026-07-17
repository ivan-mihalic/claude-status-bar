#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="${1:?usage: package.sh <version>}"
rm -rf build dist && mkdir -p dist
xcodegen generate
xcodebuild -project ClaudeStatusBar.xcodeproj -scheme ClaudeStatusBar \
  -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
APP="build/Build/Products/Release/ClaudeStatusBar.app"
# ditto preserves symlinks/permissions Sparkle needs
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/ClaudeStatusBar-$VERSION.zip"
echo "dist/ClaudeStatusBar-$VERSION.zip"
