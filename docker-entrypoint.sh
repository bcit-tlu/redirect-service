#!/bin/sh
# Validate REDIRECT_MAPPINGS and render CONFIG_JSON for the Caddyfile's
# /config.json endpoint before starting Caddy. Fails fast on malformed
# JSON so a bad deploy CrashLoops instead of silently serving no redirects.
set -eu

# Default mapping table baked into the image (KEY=VALUE per line). An
# explicit REDIRECT_MAPPINGS env var (deployment ConfigMap) overrides it.
MAPPINGS_FILE="${MAPPINGS_FILE:-/etc/redirect-service/mappings.env}"
if [ -z "${REDIRECT_MAPPINGS:-}" ] && [ -f "$MAPPINGS_FILE" ]; then
	REDIRECT_MAPPINGS=$(jq -Rn \
		'reduce (inputs | select(test("\\S")) | select(startswith("#") | not)) as $l
			({}; . + ($l | split("=") | {(.[0]): (.[1:] | join("="))}))' \
		"$MAPPINGS_FILE")
	export REDIRECT_MAPPINGS
fi

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
