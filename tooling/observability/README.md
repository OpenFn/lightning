# Local Observability

> Status: WIP. The compose file and scrape config are stable; the dashboard JSON
> is still being iterated on.

A self-contained Prometheus + Grafana stack you can run locally to see
Lightning's metrics in real time before pushing a PR. Mirrors the shape of our
production Grafana Cloud setup, so PromQL queries you build here translate
directly.

Uses [`grafana/otel-lgtm`][lgtm], which bundles Prometheus, Grafana, Tempo,
Loki, Pyroscope, and the OpenTelemetry Collector in one container. Today we only
use the Prometheus + Grafana parts; the rest is sitting there ready for when we
add tracing / log aggregation.

## What's in this folder

| File                           | Purpose                                                                               |
| ------------------------------ | ------------------------------------------------------------------------------------- |
| `docker-compose.yml`           | Runs the `grafana/otel-lgtm` container                                                |
| `prometheus.yaml`              | Tells the bundled Prometheus to scrape Phoenix at `host.docker.internal:4000/metrics` |
| `channel-proxy-dashboard.json` | Example custom dashboard for the Channels feature                                     |

## Prerequisites

- Docker + Docker Compose
- Phoenix running locally on port 4000 (the usual `iex -S mix phx.server`)
- These env vars exported in your shell (`.envrc`, `.env`, direct `export`,
  whatever you use):

  ```bash
  # Required: enable PromEx and let it serve /metrics unauthenticated locally
  export PROMEX_ENABLED=true
  export PROMEX_METRICS_ENDPOINT_AUTHORIZATION_REQUIRED=false
  export PROMEX_ENDPOINT_SCHEME=http
  export PROMEX_DATASOURCE_ID=prometheus

  # Required: lets Phoenix push the bundled PromEx dashboards into Grafana on boot
  export PROMEX_GRAFANA_HOST=http://localhost:3000
  export PROMEX_GRAFANA_USER=admin
  export PROMEX_GRAFANA_PASSWORD=admin
  export PROMEX_UPLOAD_GRAFANA_DASHBOARDS_ON_START=true
  ```

  These are also documented (commented out) in `.env.example` near the bottom
  under `# PROMEX_*`.

## Start the stack

```bash
docker compose -f tooling/observability/docker-compose.yml up -d
```

Wait ~20s for Grafana to be ready, then **restart Phoenix** so PromEx re-runs
its boot-time dashboard upload against the now-running Grafana. (The order
matters: if Phoenix boots before Grafana, the upload fails silently with a
warning in the logs.)

Verify everything's wired up:

```bash
# Grafana is alive
curl -fsS -u admin:admin http://localhost:3000/api/health

# Prometheus is scraping Phoenix successfully
open http://localhost:9090/targets   # "lightning" should be UP

# Dashboards landed
curl -fsS -u admin:admin "http://localhost:3000/api/search?type=dash-db" | jq '.[].title'
```

## What you get

Two sources of dashboards land in Grafana:

1. **PromEx-bundled dashboards**, uploaded by Phoenix on boot — `Application`,
   `BEAM`, `Phoenix`, `Ecto`, `Oban`, `PhoenixLiveView`. These ship inside the
   `prom_ex` hex package and are listed in `Lightning.PromEx.dashboards/0`
   (`lib/lightning/prom_ex.ex`). The same dashboards run in our prod Grafana
   Cloud via the same upload mechanism.
2. **Custom dashboards from this folder**, pushed manually with `curl` (see
   below). These don't auto-upload — they're for local iteration.

Open Grafana at <http://localhost:3000> (anonymous Admin is enabled, no login
needed).

## Custom dashboards: the local workflow

The dashboard JSON files here are intentionally **not** auto-uploaded. You push
them manually so you can iterate quickly without restarting Phoenix.

**Push or update a dashboard:**

```bash
curl -fsS -u admin:admin -H 'Content-Type: application/json' \
  -X POST http://localhost:3000/api/dashboards/db \
  -d "$(jq -n --slurpfile d tooling/observability/channel-proxy-dashboard.json \
        '{dashboard: $d[0], overwrite: true, message: "update"}')"
```

`overwrite: true` means re-running this replaces the existing version without
needing to delete first.

**Iterate in Grafana UI, then commit:**

1. Open the dashboard in Grafana
2. Make changes
3. **Dashboard settings (gear icon) → JSON Model**
4. Copy the JSON, paste back into the file in this folder
5. Commit

**Iterate in the JSON file:**

1. Edit the JSON
2. Re-run the `curl` push above
3. Refresh Grafana

Either way works — the UI-then-commit flow is easier for visual tweaks (colours,
layout), the JSON-then-push flow is easier for changing PromQL queries.

## Promoting a dashboard to production

When a custom dashboard is ready to ship:

1. Move the JSON file to `priv/grafana_dashboards/<name>.json`
2. Add it to `Lightning.PromEx.dashboards/0` (`lib/lightning/prom_ex.ex`):
   ```elixir
   {:lightning, "/grafana_dashboards/<name>.json"}
   ```
3. Commit and ship

Prod Lightning has the same `PROMEX_GRAFANA_*` env vars set (pointing at Grafana
Cloud) and will upload the new dashboard on its next boot, the same way it
uploads the BEAM/Phoenix/Ecto/etc dashboards today.

## Adding new metrics

Custom PromEx plugins live under `lib/lightning/**/prom_ex_plugin.ex` (e.g.
`Lightning.Channels.PromExPlugin`). Each plugin is registered in
`Lightning.PromEx.plugins/0`. Plugin telemetry events are emitted from the
relevant context module via `:telemetry.span/3` or `:telemetry.execute/3`. Once
a plugin is wired up, its metrics show up at `/metrics` automatically — no
Grafana side wiring needed beyond a panel.

## PromQL tips for sparse local traffic

A few quirks you'll hit when you're poking the app by hand instead of running
real load:

- **Counter series only exist from the first time their labels are seen.** A new
  `project_id` won't have a series until the first request — Grafana draws a
  gap, not a zero.
- **`rate()` returns null (a gap) when there are fewer than 2 samples in the
  window.** For sparse traffic, use `increase()` over a longer window, or wrap
  with `or on() vector(0)`.
- **For request volume, `increase(...[1m])` as a bar chart** is much more
  legible than `rate()` line graphs when you're testing manually. The example
  dashboard uses this pattern.

## Tear down

```bash
docker compose -f tooling/observability/docker-compose.yml down       # keeps data
docker compose -f tooling/observability/docker-compose.yml down -v    # wipes Grafana state + metrics
```

## Troubleshooting

**PromEx dashboards missing from Grafana.** Phoenix probably booted before
Grafana was ready. Restart Phoenix.

**`/metrics` returns 401.** `PROMEX_METRICS_ENDPOINT_AUTHORIZATION_REQUIRED`
defaults to `true` — set it to `false` for local dev, or include the bearer
token from `PROMEX_METRICS_ENDPOINT_TOKEN` in the scrape config.

**Prometheus target shows DOWN at <http://localhost:9090/targets>.**

- Linux: confirm the `extra_hosts: host.docker.internal:host-gateway` line in
  `docker-compose.yml` is present.
- Confirm Phoenix is bound to all interfaces (`lsof -i :4000` should show
  `*:4000`, not `127.0.0.1:4000`). If it's localhost-only, the container can't
  reach it.

**Port 3000 already in use.** Change the left side of the `3000:3000` mapping in
`docker-compose.yml` (e.g. `3001:3000`) and update `PROMEX_GRAFANA_HOST` to
match.

**Dashboard upload at Phoenix boot fails with a credentials error.**
`grafana/otel-lgtm` defaults to anonymous Admin access, but the Grafana HTTP API
still needs basic auth. The default `admin/admin` works unless you've set
`GF_SECURITY_ADMIN_PASSWORD` on the container.

[lgtm]: https://github.com/grafana/docker-otel-lgtm
