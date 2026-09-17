# redirect-service

A minimal Caddy service that shows visitors a "this site is being migrated"
splash page and redirects them to the workload's new home after a short
countdown. Built for migrations — any number of source hosts can be mapped.

## How it works

```
browser ──► https://qcon.ltc.bcit.ca
              │  HAProxy: http-request redirect
              ▼
           https://redirect.ltc.bcit.ca/?from=qcon.ltc.bcit.ca
              │  Caddy serves splash page
              ▼  (~5 s countdown)
           https://qcon-solo.ltc.bcit.ca
```

1. HAProxy issues a `302` for the migrating host, appending
   `?from=<original host>` (see [`docs/haproxy.md`](docs/haproxy.md)).
2. The splash page fetches `/config.json` and looks the `from` host up in
   the mapping table.
3. A countdown runs, a `/e/redirect` beacon is recorded, and the browser
   is sent to the mapped target. Redirects go to the target **root** —
   the original path/query is intentionally dropped.

If the `from` host is missing or not in the table, the page shows a neutral
"no redirect configured" notice and never redirects. There is no `?to=`
parameter, so the service cannot be abused as an open redirect.

## Configuration

The mapping table is a `KEY=VALUE` env file — one `host=target` per
line, `#` comments and blank lines ignored, split on the first `=` so
targets keep query strings intact:

```
qcon.ltc.bcit.ca=https://qcon-solo.ltc.bcit.ca
```

The entrypoint picks **one** file, first match wins:

1. `$MAPPINGS_FILE`, when set
2. `/etc/redirect-service/override/mappings.env` — deployer-provided
   ConfigMap (e.g. Flux `configMapGenerator`), mounted by the chart
   from the ConfigMap named by `mappingsConfigMap`
3. `/etc/redirect-service/chart/mappings.env` — the chart's own
   ConfigMap, rendered from the `mappings` value
4. `/etc/redirect-service/mappings.env` — baked into the image
   (`redirect-bcit.ltc.bcit.ca → https://bcit.ca`)

| Environment variable     | Default | Description                                              |
| ------------------------ | ------- | -------------------------------------------------------- |
| `MAPPINGS_FILE`          | —       | Explicit mapping-file path; skips the precedence search. |
| `REDIRECT_DELAY_SECONDS` | `5`     | Countdown length before the redirect fires.              |

A missing/unreadable table makes the container exit non-zero at
startup (fail fast instead of silently serving no redirects). Mapping
files are read once at startup — a ConfigMap content change alone does
not apply until the pods restart (the chart's `checksum/config`
annotation handles this for its own ConfigMap; restart the deployment
after changing an override ConfigMap).

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
| `/config.json` | `{"delaySeconds":N,"mappings":{...}}`            |
| `/e/redirect`  | 204 beacon recorded before browser navigation.   |
| `/metrics`     | Prometheus metrics.                              |
| `/healthz`     | Liveness/readiness.                              |

## Local testing

```bash
docker compose up --build

# then:
curl -s localhost:8080/healthz
curl -s localhost:8080/config.json
curl -s 'localhost:8080/?from=qcon.ltc.bcit.ca'
open 'http://localhost:8080/?from=qcon.ltc.bcit.ca'   # watch the countdown
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
  --set mappings.'qcon\.ltc\.bcit\.ca'=https://qcon-solo.ltc.bcit.ca \
  --set metrics.podMonitor.enabled=true
```

Cluster rollout is managed by Flux — see the tracking issue in
`bcit-tlu/flux-fleet`. The HAProxy side of the flow (edge ACL that 302s the
migrating host to `redirect.ltc.bcit.ca`) is documented in
[`docs/haproxy.md`](docs/haproxy.md).

## License

MPL-2.0 — see [LICENSE](LICENSE).
