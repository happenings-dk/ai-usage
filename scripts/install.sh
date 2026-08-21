#!/usr/bin/env bash
set -euo pipefail

REPO="${AI_USAGE_REPO:-happenings-dk/ai-usage}"
INSTALL_DIR="${AI_USAGE_INSTALL_DIR:-$HOME/Applications}"
APP_NAME="AiUsageMenu.app"
EXPECTED_BUNDLE_IDENTIFIER="com.rasmusjensing.ai-usage-menu"
EXPECTED_TEAM_IDENTIFIER="9JLJ6MJLMJ"
REQUESTED_VERSION="${AI_USAGE_VERSION:-latest}"
LAUNCH_APP="${AI_USAGE_LAUNCH:-1}"
MAX_ARCHIVE_BYTES=262144000
MAX_EXPANDED_ARCHIVE_BYTES=1073741824
MAX_EXPANDED_ENTRY_BYTES=262144000
TMP_DIR=""
INSTALL_STAGING_DIR=""

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
  if [ -n "$INSTALL_STAGING_DIR" ] && [ -d "$INSTALL_STAGING_DIR" ]; then
    rm -rf "$INSTALL_STAGING_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Install AI Usage from GitHub Releases.

Usage: install.sh [options]

Options:
  --version X.Y.Z      Install a specific release instead of latest
  --install-dir PATH   Install under PATH (default: ~/Applications)
  --no-launch          Install without opening the app
  -h, --help           Show this help

Environment overrides:
  AI_USAGE_REPO, AI_USAGE_INSTALL_DIR, AI_USAGE_VERSION, AI_USAGE_LAUNCH
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || { echo "--version requires X.Y.Z" >&2; exit 1; }
      REQUESTED_VERSION="$2"
      shift 2
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || { echo "--install-dir requires a path" >&2; exit 1; }
      INSTALL_DIR="$2"
      shift 2
      ;;
    --no-launch)
      LAUNCH_APP=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command curl
require_command ditto
require_command codesign
require_command unzip

if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "AI_USAGE_REPO must use owner/repository format" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
TMP_DIR="$(mktemp -d)"
INSTALL_STAGING_DIR="$(mktemp -d "${INSTALL_DIR}/.ai-usage-install.XXXXXX")"
target="${INSTALL_DIR}/${APP_NAME}"
backup_app="${INSTALL_DIR}/.${APP_NAME}.previous"

if [ ! -e "$target" ] && [ -e "$backup_app" ]; then
  echo "Recovering the previous AI Usage installation..."
  mv "$backup_app" "$target"
fi

if [ "$REQUESTED_VERSION" = "latest" ]; then
  echo "Finding the latest AI Usage release..."
  release_url="$(
    curl -fsSL \
      --retry 3 \
      -o /dev/null \
      -w '%{url_effective}' \
      "https://github.com/${REPO}/releases/latest"
  )"
  tag="${release_url##*/}"
else
  tag="v${REQUESTED_VERSION#v}"
fi

version="${tag#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Could not resolve a valid AI Usage release version" >&2
  exit 1
fi

asset_name="AIUsageMenu-${version}.zip"
release_base_url="https://github.com/${REPO}/releases/download/${tag}"
archive="${TMP_DIR}/${asset_name}"
checksums="${TMP_DIR}/checksums.txt"
extract_dir="${TMP_DIR}/extract"

echo "Downloading AI Usage ${version}..."
curl -fL --retry 3 --max-filesize "$MAX_ARCHIVE_BYTES" "${release_base_url}/${asset_name}" -o "$archive"

if ! curl -fL --retry 3 "${release_base_url}/checksums.txt" -o "$checksums"; then
  echo "Release ${version} has no downloadable checksum manifest; installation stopped." >&2
  echo "Secure one-command installation requires AI Usage 0.2.0 or later." >&2
  exit 1
fi

expected_checksum="$(awk -v asset="$asset_name" '$2 == asset { print $1; exit }' "$checksums")"
if [ -z "$expected_checksum" ]; then
  echo "checksums.txt does not contain ${asset_name}" >&2
  exit 1
fi
actual_checksum="$(/usr/bin/shasum -a 256 "$archive" | awk '{print $1}')"
if [ "$actual_checksum" != "$expected_checksum" ]; then
  echo "Checksum verification failed for ${asset_name}" >&2
  exit 1
fi
echo "Checksum verified."

archive_listing="$(unzip -Z1 "$archive")"
entry_count="$(printf '%s\n' "$archive_listing" | awk 'NF { count += 1 } END { print count + 0 }')"
if [ "$entry_count" -eq 0 ] || [ "$entry_count" -gt 10000 ]; then
  echo "Downloaded archive has an unsafe number of entries" >&2
  exit 1
fi
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  case "$entry" in
    /*|../*|*/../*|*/..)
      echo "Downloaded archive contains an unsafe path: ${entry}" >&2
      exit 1
      ;;
    AiUsageMenu.app/*|AiUsageMenu.app|__MACOSX/*|__MACOSX)
      ;;
    *)
      echo "Downloaded archive contains an unexpected top-level entry: ${entry}" >&2
      exit 1
      ;;
  esac
done <<EOF
$archive_listing
EOF

size_report="$(
  unzip -Z -l "$archive" | awk '
    $1 ~ /^[-dl]/ && $4 ~ /^[0-9]+$/ {
      count += 1
      total += $4
      if ($4 > largest) largest = $4
    }
    END { print count + 0, total + 0, largest + 0 }
  '
)"
read -r sized_entry_count expanded_bytes largest_entry_bytes <<EOF
$size_report
EOF
if [ "$sized_entry_count" -ne "$entry_count" ]; then
  echo "Could not validate every downloaded archive entry size" >&2
  exit 1
fi
if [ "$expanded_bytes" -gt "$MAX_EXPANDED_ARCHIVE_BYTES" ] \
  || [ "$largest_entry_bytes" -gt "$MAX_EXPANDED_ENTRY_BYTES" ]; then
  echo "Downloaded archive expands beyond the safe installation limit" >&2
  exit 1
fi

mkdir -p "$extract_dir"
ditto -x -k "$archive" "$extract_dir"

app_path="${extract_dir}/${APP_NAME}"
if [ ! -d "$app_path" ] || [ -L "$app_path" ]; then
  echo "Downloaded archive did not contain a .app bundle" >&2
  exit 1
fi

staged_app="${INSTALL_STAGING_DIR}/${APP_NAME}"

ditto "$app_path" "$staged_app"

bundle_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$staged_app/Contents/Info.plist")"
bundle_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$staged_app/Contents/Info.plist")"
if [ "$bundle_identifier" != "$EXPECTED_BUNDLE_IDENTIFIER" ]; then
  echo "Downloaded app has unexpected bundle identifier: ${bundle_identifier}" >&2
  exit 1
fi
if [ "$bundle_version" != "$version" ]; then
  echo "Downloaded app is version ${bundle_version}, expected ${version}" >&2
  exit 1
fi

codesign --verify --deep --strict "$staged_app"
signing_details="$(codesign -d --verbose=4 "$staged_app" 2>&1)"
team_identifier="$(printf '%s\n' "$signing_details" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
if [ "$team_identifier" != "$EXPECTED_TEAM_IDENTIFIER" ]; then
  echo "Downloaded app has unexpected Developer ID team: ${team_identifier:-unknown}" >&2
  exit 1
fi
/usr/sbin/spctl --assess --type execute --verbose=2 "$staged_app"

echo "Installing to ${target}..."
if [ -e "$target" ]; then
  if [ -e "$backup_app" ]; then
    rm -rf "$backup_app"
  fi
  mv "$target" "$backup_app"
fi

if ! mv "$staged_app" "$target"; then
  echo "Installation failed; restoring the previous app." >&2
  if [ -e "$backup_app" ]; then
    mv "$backup_app" "$target"
  fi
  exit 1
fi

if [ "$LAUNCH_APP" = "1" ]; then
  echo "Launching AI Usage..."
  if ! open "$target"; then
    echo "Launch failed; restoring the previous app." >&2
    rm -rf "$target"
    if [ -e "$backup_app" ]; then
      mv "$backup_app" "$target"
    fi
    exit 1
  fi
fi

echo "Installed AI Usage ${version}"
echo "Release: https://github.com/${REPO}/releases/tag/${tag}"
if [ -e "$backup_app" ]; then
  echo "Previous version retained at ${backup_app}"
fi
