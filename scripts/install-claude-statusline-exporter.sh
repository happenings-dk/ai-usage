#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exporter="${script_dir}/claude-statusline-exporter.sh"
settings="${HOME}/.claude/settings.json"
backup="${settings}.ai-usage-backup-$(date +%Y%m%d%H%M%S)"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to update ${settings}" >&2
  exit 1
fi

if [ ! -f "$settings" ]; then
  mkdir -p "$(dirname "$settings")"
  printf '{}\n' > "$settings"
fi

chmod +x "$exporter"
cp "$settings" "$backup"

tmp="${settings}.tmp.$$"
jq --arg command "$exporter" '
  .statusLine = {
    type: "command",
    command: $command
  }
' "$settings" > "$tmp"
mv "$tmp" "$settings"

echo "Installed Claude status-line exporter:"
echo "  $exporter"
echo "Backed up previous settings:"
echo "  $backup"
