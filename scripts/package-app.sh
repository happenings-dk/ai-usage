#!/usr/bin/env bash
set -euo pipefail

swift build -c release

VERSION="${AI_USAGE_VERSION:-0.1.0}"
BUILD_NUMBER="${AI_USAGE_BUILD:-1}"
GITHUB_REPO="${AI_USAGE_GITHUB_REPO:-happenings-dk/ai-usage}"

APP_DIR=".build/release/AiUsageMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp ".build/release/AiUsageMenu" "$MACOS_DIR/AiUsageMenu"

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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>AIUsageGitHubRepository</key>
    <string>${GITHUB_REPO}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/AiUsageMenu"
echo "Built $APP_DIR"
