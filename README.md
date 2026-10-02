# redirect-service

A minimal Caddy service that shows visitors a "this site is being migrated"
splash page and redirects them to the workload's new home after a short
countdown. Built for migrations — any number of source hosts can be mapped.

## How it works

```
browser ──► https://oldapp.example.com
              │  edge proxy: http-request redirect
              ▼
           https://redirect.example.com/?from=oldapp.example.com
              │  Caddy serves splash page
              ▼  (~5 s countdown)
           https://newapp.example.com
```

1. The edge proxy (e.g. HAProxy) issues a `302` for the migrating host,
   appending `?from=<original host>` (see [`docs/haproxy.md`](docs/haproxy.md)).
2. The splash page fetches `/config.json` and looks the `from` host up in
   the mapping table.
3. A countdown runs, a `/e/redirect` beacon is recorded, and the browser
   is sent to the mapped target. Redirects go to the target **root** —
   the original path/query is intentionally dropped.

When the proxy preserves the request `Host` instead of issuing a 302 —
e.g. a wildcard catch-all Ingress forwarding unknown hosts — the splash
uses `location.hostname` as the `from` key and the page is served on the
original hostname.

If the `from` host is not in the table but a `default_url` is configured,
the page shows a generic "address not in service" notice and redirects to
that URL after `default_delay_seconds` — this is the catch-all path for a
wildcard-ingress deployment (see [`docs/haproxy.md`](docs/haproxy.md)). With
no `default_url`, unmapped hosts keep the neutral "no redirect configured"
notice and never redirect. There is no `?to=` parameter, so the service
cannot be abused as an open redirect; `?from` and the request hostname are
lookup keys only and are never rendered into the page.

## Configuration

The mapping table is a `KEY=VALUE` env file — one `host=target` per
line, `#` comments and blank lines ignored, split on the first `=` so
targets keep query strings intact. Three reserved directive keys are
not host mappings — `delay_seconds` (migration countdown),
`default_url` (fallback target for unmapped hosts), and
`default_delay_seconds` (its countdown; falls back to `delay_seconds`):

```
delay_seconds=5
default_url=https://www.example.com/
default_delay_seconds=3
oldapp.example.com=https://newapp.example.com
```

The entrypoint picks **one** file, first match wins:

1. `$MAPPINGS_FILE`, when set
2. `/etc/redirect-service/override/mappings.env` — deployer-provided
   ConfigMap (e.g. Flux `configMapGenerator`), mounted by the chart
   from the ConfigMap named by `mappingsConfigMap`
3. `/etc/redirect-service/chart/mappings.env` — the chart's own
   ConfigMap, rendered from the `mappings`, `delaySeconds`,
   `defaultUrl`, and `defaultDelaySeconds` values
4. `/etc/redirect-service/mappings.env` — baked into the image
   (empty by default)

| Environment variable     | Default | Description                                              |
| ------------------------ | ------- | -------------------------------------------------------- |
| `MAPPINGS_FILE`          | —       | Explicit mapping-file path; skips the precedence search. |
| `REDIRECT_DELAY_SECONDS` | `5`     | Countdown fallback when the file has no `delay_seconds`.   |

A missing/unreadable table at **startup** makes the container exit
non-zero (fail fast instead of silently serving no redirects).

**Live updates:** a watcher polls the effective file every 5s and
re-renders the served `/config.json`, so editing a mounted ConfigMap
(e.g. via `kubectl edit cm` or the Rancher UI) takes effect
within ~a minute (kubelet ConfigMap sync + poll interval) — no pod
restart needed, including when the override ConfigMap is *created*
after the pod started. A failed re-render keeps the last good config.
Note that in a GitOps-managed deployment the controller will revert
out-of-band ConfigMap edits on its next reconcile — durable changes
belong in Git.

## Telemetry

- **JSON access logs** on stdout — each splash hit records
  `request.uri` (carrying `?from=<source host>`), `host`, `status`,
  `duration`. Per-source redirect volume is a log query away.
- **`/e/redirect` beacon** — the page POSTs `?from=<src>&to=<dst>` just
  before navigating, distinguishing "saw the splash" from "followed
  through".
- **`/metrics`** — Caddy's built-in Prometheus metrics
  (`caddy_http_requests_total`, duration/size histograms). `from`/`to`
  stay in logs, never metric labels (cardinality hygiene).
- **`/healthz`** — probe endpoint; excluded from access logs along with
  `/metrics`.

## Endpoints

| Path           | Purpose                                          |
| -------------- | ------------------------------------------------ |
| `/`            | Splash page (expects `?from=<host>`).            |
| `/config.json` | `{"delaySeconds":N,"defaultUrl":"…"|null,"defaultDelaySeconds":N,"mappings":{…}}` |
| `/e/redirect`  | 204 beacon recorded before browser navigation.   |
| `/metrics`     | Prometheus metrics.                              |
| `/healthz`     | Liveness/readiness.                              |

## Local testing

```bash
docker compose up --build

# then:
curl -s localhost:8080/healthz
curl -s localhost:8080/config.json
curl -s 'localhost:8080/?from=oldapp.example.com'
open 'http://localhost:8080/?from=oldapp.example.com'   # watch the countdown
```

Or without compose — the image's baked-in table serves by default; mount
a file to override:

```bash
docker build -t redirect-service .
docker run --rm -p 8080:8080 redirect-service                      # defaults
docker run --rm -p 8080:8080 \
  -v "$PWD/mappings.env:/etc/redirect-service/override/mappings.env:ro" \
  redirect-service                                                 # override
```

## Deployment

The `charts/redirect` Helm chart renders a Deployment + Service (+ optional
Ingress, NetworkPolicy, and PodMonitor):

```bash
helm install redirect charts/redirect \
  --set mappings.'oldapp\.example\.com'=https://newapp.example.com \
  --set metrics.podMonitor.enabled=true
```

The HAProxy side of the flow (edge ACL that 302s the migrating host to
the splash host) is documented in [`docs/haproxy.md`](docs/haproxy.md).

## License

MPL-2.0 — see [LICENSE](LICENSE).
