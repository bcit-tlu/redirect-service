#!/bin/sh
# Render /config.json's body from a KEY=VALUE mapping file, then start
# Caddy. A background poll re-renders when the effective file changes —
# mounted ConfigMap volumes update in place, so cluster-side edits take
# effect without a pod restart. Fails fast at startup when no table can
# be read; later render failures keep the last good config.
set -eu

RUN_DIR=/tmp/redirect-run
CONFIG_OUT="$RUN_DIR/config.json"

# Mapping file precedence, first match wins: explicit MAPPINGS_FILE >
# deployer override ConfigMap > chart ConfigMap > file baked into the
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

# One directive + mappings per file: 'delay_seconds=N' sets the
# countdown (default: $REDIRECT_DELAY_SECONDS env, then 5); every other
# line is host=target. '#' comments and blank lines ignored; split on
# the first '=' so target URLs keep query strings intact. Mapping keys
# are normalized to lowercase. Atomic write (tmp + mv) so file_server
# never serves a partial body.
render() {
	f=$(mappings_file)
	[ -n "$f" ] || {
		echo "redirect: no readable mappings file" >&2
		return 1
	}
	tmp="$RUN_DIR/.config.json.$$"
	jq -Rn \
		--arg delayenv "${REDIRECT_DELAY_SECONDS:-5}" \
		'def toint: tonumber? // null;
		 reduce (inputs | select(test("\\S")) | select(startswith("#") | not)) as $l
			({mappings: {}, delay: null};
			 ($l | split("=")) as $kv
			 | if ($kv[0] | ascii_downcase) == "delay_seconds"
				then .delay = (($kv[1:] | join("=")) | toint)
				else .mappings += {($kv[0]): ($kv[1:] | join("="))}
				end)
		 | {delaySeconds: (.delay // ($delayenv | toint) // 5),
			mappings: (.mappings | with_entries(.key |= ascii_downcase))}' \
		"$f" > "$tmp" || return 1
	mv "$tmp" "$CONFIG_OUT"
}

# Content hash of the effective file — any change triggers a re-render.
# Hash, not mtime: ConfigMap mounts swap symlinks and may preserve
# timestamps.
sig() {
	f=$(mappings_file || true)
	[ -n "$f" ] && cksum "$f"
}

mkdir -p "$RUN_DIR"
render
sig_cur=$(sig)

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
