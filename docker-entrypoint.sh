#!/bin/sh
# Render CONFIG_JSON for the Caddyfile's /config.json endpoint before
# starting Caddy. The mapping table comes solely from a KEY=VALUE env file.
# Fails fast when no table can be read.
set -eu

# Mapping table precedence: explicit MAPPINGS_FILE > deployer override
# ConfigMap > chart ConfigMap > table baked into the image.
MAPPINGS_FILE="${MAPPINGS_FILE:-}"
if [ -z "$MAPPINGS_FILE" ]; then
	for f in /etc/redirect-service/override/mappings.env \
		/etc/redirect-service/chart/mappings.env \
		/etc/redirect-service/mappings.env; do
		if [ -f "$f" ]; then
			MAPPINGS_FILE="$f"
			break
		fi
	done
fi

# host=target per line; '#' comments and blank lines ignored; split on
# the first '=' so target URLs keep query strings intact.
REDIRECT_MAPPINGS=$(jq -Rn \
	'reduce (inputs | select(test("\\S")) | select(startswith("#") | not)) as $l
		({}; . + ($l | split("=") | {(.[0]): (.[1:] | join("="))}))' \
	"$MAPPINGS_FILE")
export REDIRECT_MAPPINGS

echo "$REDIRECT_MAPPINGS" | jq -e 'type == "object"' >/dev/null

# Normalize mapping keys to lowercase bare hosts and merge the delay into
# the single payload the Caddyfile serves.
CONFIG_JSON=$(jq -nc \
	--argjson map "$REDIRECT_MAPPINGS" \
	--argjson delay "${REDIRECT_DELAY_SECONDS:-5}" \
	'{delaySeconds: $delay, mappings: ($map | with_entries(.key |= ascii_downcase))}')
export CONFIG_JSON

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
