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

# Directives + mappings per file: 'delay_seconds=N' sets the migration
# countdown (default: $REDIRECT_DELAY_SECONDS env, then 5);
# 'default_url=URL' is the fallback target for hosts with no mapping and
# 'default_delay_seconds=N' its countdown (default: delay_seconds, then
# the same env/5 chain); every other line is host=target. '#' comments
# and blank lines ignored; split on the first '=' so target URLs keep
# query strings intact. Mapping keys are normalized to lowercase.
# Atomic write (tmp + mv) so file_server never serves a partial body.
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
			({mappings: {}, delay: null, default_url: null, default_delay: null};
			 ($l | split("=")) as $kv
			 | ($kv[0] | ascii_downcase) as $key
			 | ($kv[1:] | join("=")) as $val
			 | if $key == "delay_seconds" then .delay = ($val | toint)
				elif $key == "default_url" then .default_url = $val
				elif $key == "default_delay_seconds" then .default_delay = ($val | toint)
				else .mappings += {($kv[0]): $val}
				end)
		 | .delay as $d
		 | {delaySeconds: ($d // ($delayenv | toint) // 5),
			defaultUrl: .default_url,
			defaultDelaySeconds: (.default_delay // $d // ($delayenv | toint) // 5),
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
