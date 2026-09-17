# HAProxy configuration for migration redirects

This service expects the edge proxy (HAProxy, `haproxy-configs` repo) to
302 migrating hosts to `https://redirect.ltc.bcit.ca/?from=<host>`. The
`splash` page looks `<host>` up in its mapping table (`mappings.env`)
and sends the browser to the mapped target after the countdown.

## Prerequisites

- DNS record for `redirect.ltc.bcit.ca` pointing at the HAProxy frontend.
- TLS coverage for `redirect.ltc.bcit.ca` on that frontend — already
  covered if the frontend loads a `*.ltc.bcit.ca` certificate; otherwise
  add the cert.
- The `redirect` Service reachable from HAProxy (in-cluster service DNS,
  NodePort, or however `haproxy-configs` reaches cluster workloads —
  adjust the `server` line below to match existing backends).

## Frontend ACLs

```haproxy
frontend https_in                          # existing TLS-terminating frontend
    acl host_qcon     hdr(host) -i qcon.ltc.bcit.ca
    acl host_redirect hdr(host) -i redirect.ltc.bcit.ca

    # Migration splash: bounce qcon traffic to the redirect service.
    # `from` carries the original host so the splash can resolve its
    # target from the mapping table. Remove this line when the migration
    # completes.
    http-request redirect location https://redirect.ltc.bcit.ca/?from=%[req.hdr(host)] code 302 if host_qcon
    use_backend redirect_splash if host_redirect
```

## Backend

```haproxy
backend redirect_splash
    option forwardfor
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Original-Host %[req.hdr(Host)]
    # Adjust to how haproxy-configs reaches cluster services:
    server splash redirect.<namespace>.svc.cluster.local:80 check resolvers dns resolve-prefer ipv4
```

`option forwardfor` (X-Forwarded-For) and `X-Original-Host` keep client IP
and original host available in the service's JSON access logs; neither is
strictly required for the redirect to work, but both are recommended for
telemetry.

## Adding another migration

Per service being migrated, add one ACL + one redirect line:

```haproxy
    acl host_oldapp hdr(host) -i oldapp.ltc.bcit.ca
    http-request redirect location https://redirect.ltc.bcit.ca/?from=%[req.hdr(host)] code 302 if host_oldapp
```

…and a matching `host=target` line in the deployment's `mappings.env`
(Helm value `mappings`, or an override ConfigMap — see the README).

## Rollback / cutover completion

Delete the service's `http-request redirect` line (and its ACL) from
`haproxy-configs` and let the normal `use_backend` rules resume. The
redirect service and `redirect.ltc.bcit.ca` can stay up indefinitely — a
host with no ACL redirect never reaches it.

## Sanity checks after wiring

```bash
# 302 from the migrating host:
curl -sI https://qcon.ltc.bcit.ca/ | grep -i '^location:'
# → location: https://redirect.ltc.bcit.ca/?from=qcon.ltc.bcit.ca

# Splash host responds:
curl -s 'https://redirect.ltc.bcit.ca/config.json'
# → {"delaySeconds":5,"mappings":{"qcon.ltc.bcit.ca":"https://qcon-solo.ltc.bcit.ca"}}

# Health:
curl -s https://redirect.ltc.bcit.ca/healthz   # → ok
```
