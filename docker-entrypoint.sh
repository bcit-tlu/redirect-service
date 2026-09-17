#!/bin/sh
# Render /config.json's body from KEY=VALUE mapping + delay files, then
# start Caddy. A background poll re-renders when the effective files
# change — mounted ConfigMap volumes update in place, so cluster-side
# edits take effect without a pod restart. Fails fast at startup when no
# table can be read; later render failures keep the last good config.
set -eu

RUN_DIR=/tmp/redirect-run
CONFIG_OUT="$RUN_DIR/config.json"
OVERRIDE_DIR=/etc/redirect-service/override
CHART_DIR=/etc/redirect-service/chart
BAKED_FILE=/etc/redirect-service/mappings.env

# Mapping table precedence, first match wins: explicit MAPPINGS_FILE >
# deployer override ConfigMap > chart ConfigMap > table baked into the
# image. Re-resolved on every poll so an override appearing at runtime
# takes precedence without a restart.
mappings_file() {
	if [ -n "${MAPPINGS_FILE:-}" ]; then
		[ -f "$MAPPINGS_FILE" ] && printf '%s' "$MAPPINGS_FILE"
		return
	fi
	for f in "$OVERRIDE_DIR/mappings.env" \
		"$CHART_DIR/mappings.env" \
		"$BAKED_FILE"; do
		if [ -f "$f" ]; then
			printf '%s' "$f"
			return
		fi
	done
}

# Delay precedence mirrors the mapping tiers: an optional
# REDIRECT_DELAY_SECONDS key in the override or chart ConfigMap (mounted
# as a same-named file) > the env var > 5. Mounted files update live,
# unlike env vars, which are frozen at container start.
delay_seconds() {
	for f in "$OVERRIDE_DIR/REDIRECT_DELAY_SECONDS" \
		"$CHART_DIR/REDIRECT_DELAY_SECONDS"; do
		if [ -f "$f" ]; then
			cat "$f"
			return
		fi
	done
	printf '%s' "${REDIRECT_DELAY_SECONDS:-5}"
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
		--argjson delay "$(delay_seconds)" \
		'{delaySeconds: $delay, mappings: ($map | with_entries(.key |= ascii_downcase))}' \
		> "$tmp" || return 1
	mv "$tmp" "$CONFIG_OUT"
}

# Content hash of every file that feeds the render — a change to the
# effective mapping file OR either delay file triggers a re-render.
sig() {
	f=$(mappings_file || true)
	{
		[ -n "$f" ] && cksum "$f"
		for d in "$OVERRIDE_DIR/REDIRECT_DELAY_SECONDS" \
			"$CHART_DIR/REDIRECT_DELAY_SECONDS"; do
			[ -f "$d" ] && cksum "$d"
		done
	} 2>/dev/null | cksum
}

mkdir -p "$RUN_DIR"
render
sig_cur=$(sig)

# Poll for config changes (added/removed/updated files or precedence
# shifts). Content hash, not mtime — ConfigMap mounts swap symlinks and
# may preserve timestamps.
(
	while :; do
		sleep 5
		s=$(sig)
		if [ "$s" != "$sig_cur" ]; then
			if render; then
				sig_cur="$s"
				echo "redirect: reloaded config" >&2
			else
				echo "redirect: config render failed; keeping last config" >&2
			fi
		fi
	done
) &

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
