#!/bin/sh
# Render /config.json's body from a KEY=VALUE mapping file, then start
# Caddy. A background poll re-renders when the effective mapping file
# changes — mounted ConfigMap volumes update in place, so cluster-side
# edits take effect without a pod restart. Fails fast at startup when no
# table can be read; later render failures keep the last good config.
set -eu

RUN_DIR=/tmp/redirect-run
CONFIG_OUT="$RUN_DIR/config.json"

# Mapping table precedence, first match wins: explicit MAPPINGS_FILE >
# deployer override ConfigMap > chart ConfigMap > table baked into the
# image. Re-resolved on every poll so an override appearing at runtime
# takes precedence without a restart.
mappings_file() {
	if [ -n "${MAPPINGS_FILE:-}" ]; then
		[ -f "$MAPPINGS_FILE" ] && printf '%s' "$MAPPINGS_FILE"
		return
	fi
	for f in /etc/redirect-service/override/mappings.env \
		/etc/redirect-service/chart/mappings.env \
		/etc/redirect-service/mappings.env; do
		if [ -f "$f" ]; then
			printf '%s' "$f"
			return
		fi
	done
}

# host=target per line; '#' comments and blank lines ignored; split on
# the first '=' so target URLs keep query strings intact. Keys are
# normalized to lowercase. Atomic write (tmp + mv) so file_server never
# serves a partial body.
render() {
	f=$(mappings_file)
	[ -n "$f" ] || {
		echo "redirect: no readable mappings file" >&2
		return 1
	}
	map=$(jq -Rn \
		'reduce (inputs | select(test("\\S")) | select(startswith("#") | not)) as $l
			({}; . + ($l | split("=") | {(.[0]): (.[1:] | join("="))}))' \
		"$f") || return 1
	tmp="$RUN_DIR/.config.json.$$"
	jq -nc \
		--argjson map "$map" \
		--argjson delay "${REDIRECT_DELAY_SECONDS:-5}" \
		'{delaySeconds: $delay, mappings: ($map | with_entries(.key |= ascii_downcase))}' \
		> "$tmp" || return 1
	mv "$tmp" "$CONFIG_OUT"
}

mkdir -p "$RUN_DIR"
render

sig="$(mappings_file):$(cksum "$(mappings_file)" | cut -d' ' -f1-2)"

# Poll for mapping-table changes (added/removed/updated files or
# precedence shifts). Content hash, not mtime — ConfigMap mounts swap
# symlinks and may preserve timestamps.
(
	while :; do
		sleep 5
		f=$(mappings_file || true)
		[ -n "$f" ] || continue
		s="$f:$(cksum "$f" 2>/dev/null | cut -d' ' -f1-2 || true)"
		if [ "$s" != "$sig" ]; then
			if render; then
				sig="$s"
				echo "redirect: reloaded mappings from $f" >&2
			else
				echo "redirect: mappings render failed; keeping last config" >&2
			fi
		fi
	done
) &

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
