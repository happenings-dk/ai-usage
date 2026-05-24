#!/usr/bin/env bash
set -euo pipefail

REPO="${AI_USAGE_REPO:-happenings-dk/ai-usage}"
INSTALL_DIR="${AI_USAGE_INSTALL_DIR:-$HOME/Applications}"
APP_NAME="AiUsageMenu.app"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command curl
require_command ditto

mkdir -p "$INSTALL_DIR"

echo "Fetching latest AI Usage release from ${REPO}..."
release_json="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")"

asset_url="$(
  printf '%s' "$release_json" |
    /usr/bin/python3 -c '
import json
import sys

release = json.load(sys.stdin)
assets = release.get("assets", [])

def score(asset):
    name = asset.get("name", "").lower()
    if not name.endswith(".zip"):
        return -1
    if "aiusagemenu" in name or "ai-usage" in name or "ai_usage" in name:
        return 2
    return 1

best = max(assets, key=score, default=None)
if not best or score(best) < 1:
    sys.exit("No .zip app asset found on latest release")
print(best["browser_download_url"])
'
)"

version="$(
  printf '%s' "$release_json" |
    /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin).get("tag_name", "latest"))'
)"

archive="${TMP_DIR}/AIUsageMenu.zip"
extract_dir="${TMP_DIR}/extract"

echo "Downloading ${version}..."
curl -fL "$asset_url" -o "$archive"

mkdir -p "$extract_dir"
ditto -x -k "$archive" "$extract_dir"

app_path="$(find "$extract_dir" -name "$APP_NAME" -type d -maxdepth 4 | head -n 1)"
if [ -z "$app_path" ]; then
  app_path="$(find "$extract_dir" -name "*.app" -type d -maxdepth 4 | head -n 1)"
fi

if [ -z "$app_path" ]; then
  echo "Downloaded archive did not contain a .app bundle" >&2
  exit 1
fi

target="${INSTALL_DIR}/${APP_NAME}"
echo "Installing to ${target}..."
rm -rf "$target"
ditto "$app_path" "$target"
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

echo "Launching AI Usage..."
open "$target"

echo "Installed AI Usage ${version}"
