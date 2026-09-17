# HAProxy configuration for migration redirects

This service expects the edge proxy to 302 migrating hosts to
`https://redirect.example.com/?from=<host>` (examples below use
`example.com` hosts — substitute your own domains). The splash page
looks `<host>` up in its mapping table (`mappings.env`) and sends the
browser to the mapped target after the countdown.

## Prerequisites

- DNS record for `redirect.example.com` pointing at the HAProxy frontend.
- TLS coverage for `redirect.example.com` on that frontend — already
  covered if the frontend loads a `*.example.com` certificate; otherwise
  add the cert.
- The `redirect` Service reachable from HAProxy (in-cluster service DNS,
  NodePort, or however your proxy configs reach cluster workloads —
  adjust the `server` line below to match existing backends).

## Frontend ACLs

```haproxy
frontend https_in                          # existing TLS-terminating frontend
    acl host_oldapp   hdr(host) -i oldapp.example.com
    acl host_redirect hdr(host) -i redirect.example.com

    # Migration splash: bounce oldapp traffic to the redirect service.
    # `from` carries the original host so the splash can resolve its
    # target from the mapping table. Remove this line when the migration
    # completes.
    http-request redirect location https://redirect.example.com/?from=%[req.hdr(host)] code 302 if host_oldapp
    use_backend redirect_splash if host_redirect
```

## Backend

```haproxy
backend redirect_splash
    option forwardfor
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Original-Host %[req.hdr(Host)]
    # Adjust to how the proxy reaches cluster services:
    server splash redirect.<namespace>.svc.cluster.local:80 check resolvers dns resolve-prefer ipv4
```

`option forwardfor` (X-Forwarded-For) and `X-Original-Host` keep client IP
and original host available in the service's JSON access logs; neither is
strictly required for the redirect to work, but both are recommended for
telemetry.

## Adding another migration

Per service being migrated, add one ACL + one redirect line:

```haproxy
    acl host_legacy hdr(host) -i legacy.example.com
    http-request redirect location https://redirect.example.com/?from=%[req.hdr(host)] code 302 if host_legacy
```

…and a matching `host=target` line in the deployment's `mappings.env`
(Helm value `mappings`, or an override ConfigMap — see the README).

## Rollback / cutover completion

Delete the service's `http-request redirect` line (and its ACL) from the
proxy config and let the normal `use_backend` rules resume. The
redirect service and `redirect.example.com` can stay up indefinitely — a
host with no ACL redirect never reaches it.

## Sanity checks after wiring

```bash
# 302 from the migrating host:
curl -sI https://oldapp.example.com/ | grep -i '^location:'
# → location: https://redirect.example.com/?from=oldapp.example.com

# Splash host responds:
curl -s 'https://redirect.example.com/config.json'
# → {"delaySeconds":5,"mappings":{"oldapp.example.com":"https://newapp.example.com"}}

# Health:
curl -s https://redirect.example.com/healthz   # → ok
```
