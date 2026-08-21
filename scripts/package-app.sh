#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="${AI_USAGE_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${AI_USAGE_BUILD:-1}"
GITHUB_REPO="${AI_USAGE_GITHUB_REPO:-happenings-dk/ai-usage}"
UNIVERSAL_BUILD="${AI_USAGE_UNIVERSAL:-1}"
SIGNING_IDENTITY="${AI_USAGE_SIGNING_IDENTITY:--}"
TEAM_IDENTIFIER="${AI_USAGE_TEAM_IDENTIFIER:-9JLJ6MJLMJ}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "AI_USAGE_VERSION must use X.Y.Z format (received: ${VERSION})" >&2
  exit 1
fi

SWIFT_BUILD_ARGUMENTS=(-c release)
if [ "$UNIVERSAL_BUILD" = "1" ]; then
  SWIFT_BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
fi

swift build "${SWIFT_BUILD_ARGUMENTS[@]}"
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"

APP_DIR=".build/release/AiUsageMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
ICON_SOURCE="apple/Apps/iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
ICONSET_DIR=".build/release/AIUsage.iconset"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR"

cp "${BIN_DIR}/AiUsageMenu" "$MACOS_DIR/AiUsageMenu"
cp "${BIN_DIR}/AIUsageUpdaterHelper" "$HELPERS_DIR/AIUsageUpdaterHelper"

if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [ -f "$ICON_SOURCE" ]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AIUsage.icns"
  rm -rf "$ICONSET_DIR"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AiUsageMenu</string>
    <key>CFBundleIdentifier</key>
    <string>com.rasmusjensing.ai-usage-menu</string>
    <key>CFBundleName</key>
    <string>AI Usage</string>
    <key>CFBundleDisplayName</key>
    <string>AI Usage</string>
    <key>CFBundleIconFile</key>
    <string>AIUsage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>AIUsageGitHubRepository</key>
    <string>${GITHUB_REPO}</string>
    <key>AIUsageExpectedTeamIdentifier</key>
    <string>${TEAM_IDENTIFIER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/AiUsageMenu"
chmod +x "$HELPERS_DIR/AIUsageUpdaterHelper"

# SwiftPM signs the executable before the app resources exist. Sign the final
# bundle so adding the icon and Info.plist does not leave an invalid seal.
if command -v codesign >/dev/null 2>&1; then
  if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_DIR"
  else
    codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --sign "$SIGNING_IDENTITY" \
      "$APP_DIR"
  fi
  codesign --verify --deep --strict "$APP_DIR"
fi

echo "Built $APP_DIR"
