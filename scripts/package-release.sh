#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="${AI_USAGE_VERSION:-$(tr -d '[:space:]' < VERSION)}"
GITHUB_REPO="${AI_USAGE_GITHUB_REPO:-happenings-dk/ai-usage}"
SKIP_BUILD="${AI_USAGE_SKIP_BUILD:-0}"
DIST_DIR=".build/dist"
APP_DIR=".build/release/AiUsageMenu.app"
ZIP_PATH="${DIST_DIR}/AIUsageMenu-${VERSION}.zip"
DMG_PATH="${DIST_DIR}/AIUsageMenu.dmg"
UPDATE_JSON="${DIST_DIR}/update.json"
CHECKSUMS_PATH="${DIST_DIR}/checksums.txt"
DMG_STAGING_DIR=".build/dmg-staging"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "AI_USAGE_VERSION must use X.Y.Z format (received: ${VERSION})" >&2
  exit 1
fi

if [ "$SKIP_BUILD" != "1" ]; then
  AI_USAGE_VERSION="$VERSION" \
    AI_USAGE_GITHUB_REPO="$GITHUB_REPO" \
    scripts/package-app.sh
fi

if [ ! -d "$APP_DIR" ]; then
  echo "Missing app bundle: ${APP_DIR}" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DIST_DIR" "$DMG_STAGING_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

/usr/bin/ditto "$APP_DIR" "$DMG_STAGING_DIR/AiUsageMenu.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
/usr/bin/hdiutil create \
  -volname "AI Usage" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING_DIR"

ZIP_SHA256="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

cat > "$UPDATE_JSON" <<JSON
{
  "version": "${VERSION}",
  "download_url": "https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/AIUsageMenu-${VERSION}.zip",
  "sha256": "${ZIP_SHA256}",
  "minimum_macos_version": "14.0"
}
JSON

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 \
    "$(basename "$ZIP_PATH")" \
    "$(basename "$DMG_PATH")"
) > "$CHECKSUMS_PATH"

echo "Release assets:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $CHECKSUMS_PATH"
echo "  $UPDATE_JSON"
echo
echo "Create a GitHub release:"
echo "  gh release create v${VERSION} $ZIP_PATH $DMG_PATH $CHECKSUMS_PATH $UPDATE_JSON --title v${VERSION} --generate-notes"
