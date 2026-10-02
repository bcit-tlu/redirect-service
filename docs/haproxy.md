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

## Catch-all for unknown hosts (wildcard ingress)

An alternative topology for "any unmatched `*.example.com` host should
get the splash": instead of an edge 302, let unmatched hosts fall
through to the cluster ingress controller (e.g. HAProxy's
`default_backend`) and give the redirect Ingress a wildcard host:

```yaml
ingress:
  hosts:
    - host: redirect.example.com   # exact splash host
      paths: [{ path: /, pathType: Prefix }]
    - host: "*.example.com"        # catch-all — exact matches always win
      paths: [{ path: /, pathType: Prefix }]
  tls:
    - hosts: [redirect.example.com, "*.example.com"]
      secretName: <wildcard-cert-secret>
```

The page resolves `from` from `location.hostname` when `?from` is
absent, so `anything.example.com` serves the splash on its own hostname.
Unmapped hosts redirect to the configured `default_url` after
`default_delay_seconds` (without `default_url` they get the neutral
notice). Notes:

- Ingress wildcard hosts match a single DNS label only
  (`a.b.example.com` is not covered) — typically the same limit as the
  wildcard TLS cert anyway.
- One wildcard owner per ingress controller: if another Ingress claims
  `*.example.com`, the controller picks one.
- Keep the redirect service pod-scoped tight when it answers on
  arbitrary hostnames: the chart's `networkPolicy` + the Caddyfile's
  CSP/`no-store` headers are the guardrails; a hostPort/hostNetwork
  ingress controller's traffic arrives with node source IPs, so verify
  before restricting `allowedNamespaces`.

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
