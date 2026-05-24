#!/usr/bin/env bash
set -euo pipefail

VERSION="${AI_USAGE_VERSION:-0.1.0}"
GITHUB_REPO="${AI_USAGE_GITHUB_REPO:-happenings-dk/ai-usage}"
DIST_DIR=".build/dist"
APP_DIR=".build/release/AiUsageMenu.app"
ZIP_PATH="${DIST_DIR}/AIUsageMenu-${VERSION}.zip"
UPDATE_JSON="${DIST_DIR}/update.json"

AI_USAGE_VERSION="$VERSION" AI_USAGE_GITHUB_REPO="$GITHUB_REPO" scripts/package-app.sh

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

cat > "$UPDATE_JSON" <<JSON
{
  "version": "${VERSION}",
  "download_url": "https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/AIUsageMenu-${VERSION}.zip"
}
JSON

echo "Release assets:"
echo "  $ZIP_PATH"
echo "  $UPDATE_JSON"
echo
echo "Create a GitHub release:"
echo "  gh release create v${VERSION} $ZIP_PATH $UPDATE_JSON --title v${VERSION} --notes \"AI Usage ${VERSION}\""
