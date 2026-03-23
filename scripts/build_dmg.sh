#!/bin/zsh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CuePane"
VERSION="${CUEPANE_VERSION:-0.2.0}"
DIST_DIR="$REPO_ROOT/dist"
STAGE_DIR="$REPO_ROOT/.build/dmg-stage"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_PATH="$(swift build -c release --package-path "$REPO_ROOT" --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/$APP_NAME"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
SIGNING_IDENTITY="${CUEPANE_SIGNING_IDENTITY:-CuePane Local Signer}"
SIGNING_KEYCHAIN_PATH="${CUEPANE_SIGNING_KEYCHAIN_PATH:-$HOME/.cuepane-local-signing/CuePaneLocal.keychain-db}"

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DIST_DIR"

swift build -c release --package-path "$REPO_ROOT"
"$REPO_ROOT/scripts/generate_app_icon.sh"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$REPO_ROOT/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>CuePane</string>
  <key>CFBundleExecutable</key>
  <string>CuePane</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>dev.cuepane.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>CuePane</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SUPublicEDKey</key>
  <string>FVXsi1mAJvPgsjUCmA9vJxk6A0Pio3uBEKGccH8HyXw=</string>
  <key>SUFeedURL</key>
  <string>https://kanguk01.github.io/CuePane/appcast.xml</string>
</dict>
</plist>
PLIST

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  CUEPANE_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  CUEPANE_SIGNING_KEYCHAIN_PATH="$SIGNING_KEYCHAIN_PATH" \
    "$REPO_ROOT/scripts/ensure_local_signing_identity.sh" >/dev/null
  codesign --force --deep --keychain "$SIGNING_KEYCHAIN_PATH" --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created DMG: $DMG_PATH"
