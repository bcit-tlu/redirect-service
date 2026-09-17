#!/bin/sh
# Validate REDIRECT_MAPPINGS and render CONFIG_JSON for the Caddyfile's
# /config.json endpoint before starting Caddy. Fails fast on malformed
# JSON so a bad deploy CrashLoops instead of silently serving no redirects.
set -eu

: "${REDIRECT_MAPPINGS:={}}"

echo "$REDIRECT_MAPPINGS" | jq -e 'type == "object"' >/dev/null

# Normalize mapping keys to lowercase bare hosts and merge the delay into
# the single payload the Caddyfile serves.
CONFIG_JSON=$(jq -nc \
	--argjson map "$REDIRECT_MAPPINGS" \
	--argjson delay "${REDIRECT_DELAY_SECONDS:-5}" \
	'{delaySeconds: $delay, mappings: ($map | with_entries(.key |= ascii_downcase))}')
export CONFIG_JSON

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
