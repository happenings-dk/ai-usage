#!/bin/sh

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: ./configure-relay.sh <worker-base-url> [channel]" >&2
  exit 64
fi

relay_base_url=${1%/}
relay_channel=${2:-$(hostname -s | tr -cd '[:alnum:]_-')}

case "$relay_base_url" in
  https://*) ;;
  *)
    echo "The Worker URL must start with https://" >&2
    exit 64
    ;;
esac

if [ -z "$relay_channel" ]; then
  echo "The channel must contain letters, numbers, dashes, or underscores." >&2
  exit 64
fi

relay_token=$(openssl rand -hex 32)
printf '%s' "$relay_token" | npx wrangler secret put RELAY_TOKEN

relay_config_directory="$HOME/.ai-usage"
relay_config_file="$relay_config_directory/relay.json"
relay_temporary_file=$(mktemp)
trap 'rm -f "$relay_temporary_file"' EXIT HUP INT TERM

jq -n \
  --arg base_url "$relay_base_url" \
  --arg channel "$relay_channel" \
  --arg token "$relay_token" \
  '{base_url: $base_url, channel: $channel, token: $token}' > "$relay_temporary_file"
mkdir -p "$relay_config_directory"
install -m 600 "$relay_temporary_file" "$relay_config_file"

echo "Configured channel '$relay_channel' in $relay_config_file."
echo "Restart AI Usage Menu and scan its pairing QR again."
