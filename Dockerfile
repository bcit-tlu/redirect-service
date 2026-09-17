# Redirect splash service
#
# Base: caddy:2-alpine (major-pinned, matching org convention for
# postgres:16-alpine / redis:7-alpine). Single-stage image with an
# explicit `stable` target name so the OCI build workflow can share a
# uniform `target: stable` matrix entry across components.
FROM caddy:2-alpine AS stable

# jq validates and normalizes REDIRECT_MAPPINGS at container start.
RUN apk add --no-cache jq

# The base image grants /usr/bin/caddy the cap_net_bind_service file
# capability for privileged ports. We bind unprivileged :8080 only, and
# the deployment drops ALL capabilities — the kernel refuses execve of a
# file-cap binary absent from the bounding set (EPERM), so strip it.
RUN setcap -r /usr/bin/caddy

COPY Caddyfile /etc/caddy/Caddyfile
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY mappings.env /etc/redirect-service/mappings.env
COPY site/ /srv/

RUN chmod +x /docker-entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
