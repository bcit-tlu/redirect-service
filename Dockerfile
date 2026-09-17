# Redirect splash service
#
# Base: caddy:2-alpine (major-pinned, matching org convention for
# postgres:16-alpine / redis:7-alpine). Single-stage image with an
# explicit `stable` target name so the OCI build workflow can share a
# uniform `target: stable` matrix entry across components.
FROM caddy:2-alpine AS stable

# jq validates and normalizes REDIRECT_MAPPINGS at container start.
RUN apk add --no-cache jq

COPY Caddyfile /etc/caddy/Caddyfile
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY site/ /srv/

RUN chmod +x /docker-entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
