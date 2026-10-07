# Running Lightning Locally

This guide provides instructions for running Lightning locally, either by
installing dependencies on your machine or using Docker.

## By Installing Dependencies

### Setup

#### Postgres

Requires `postgres 15`. When running in `dev` mode, the app will use the
following credentials to authenticate:

- `PORT`: `5432`
- `USER`: `postgres`
- `PASSWORD`: `postgres`
- `DATABASE`: `lightning_dev`

This can however be overridden by specifying a `DATABASE_URL` env var. e.g.
`DATABASE_URL=postgresql://postgres:postgres@localhost:5432/lightning_dev`

We recommend that you use docker for running postgres as you'll get an exact
version that we use:

```sh
docker volume create lightning-postgres-data

docker create \
  --name lightning-postgres \
  --mount source=lightning-postgres-data,target=/var/lib/postgresql/data \
  --publish 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  postgres:15.3-alpine

docker start lightning-postgres
```

#### Elixir, NodeJS

We use [asdf](https://github.com/asdf-vm/asdf) to configure our local
environments. Included in the repo is a `.tool-versions` file that is read by
asdf in order to dynamically make the specified versions of Elixir, Erlang and
NodeJs available. You'll need asdf plugins for
[Erlang](https://github.com/asdf-vm/asdf-erlang),
[NodeJs](https://github.com/asdf-vm/asdf-nodejs)
[Elixir](https://github.com/asdf-vm/asdf-elixir) and
[k6](https://github.com/grimoh/asdf-k6).

#### Libsodium

We use [libsodium](https://doc.libsodium.org/) for encoding values as required
by the
[Github API](https://docs.github.com/en/rest/guides/encrypting-secrets-for-the-rest-api).
You'll need to install `libsodium` in order for the application to compile.

For Mac Users:

```sh
brew install libsodium
```

For Debian Users:

```sh
sudo apt-get install libsodium-dev
```

You can find more on
[how to install libsodium here](https://doc.libsodium.org/installation)

#### Compilation and Assets

```sh
asdf install  # Install language versions
mix local.hex
mix deps.get
mix local.rebar --force
[[ $(uname -m) == 'arm64' ]] && CPATH=/opt/homebrew/include LIBRARY_PATH=/opt/homebrew/lib mix deps.compile enacl # Force compile enacl if on M1
mix lightning.install_runtime
mix ecto.create
mix ecto.migrate
npm install --prefix assets
```

In case you encounter errors running any of these commands, see the
[troubleshooting guide](README.md#troubleshooting) for known errors.

### Running the App

To start the lightning server:

```sh
mix phx.server
```

Once the server has started, head to [`localhost:4000`](http://localhost:4000)
in your browser.

By default, the `worker` is started when run `mix phx.server` in `dev` mode. In
case you don't want to have your worker started in `dev`, set `RTM=false`:

```sh
RTM=false mix phx.server
```

## Using Docker

There is an existing `docker-compose.yaml` file in the project's root which has
all the services required. To start your services:

```sh
docker compose up
```

There 2 docker files in the root, `Dockerfile` builds the app in `prod` mode
while `Dockerfile-dev` runs it in `dev` mode. It is important to note that
`mix commands` do not work in the `prod` images.

For example, to run migrations in `dev` mode you run:

```sh
docker compose run --rm web mix ecto.migrate
```

While in `prod` mode:

```sh
docker compose run --rm web /app/bin/lightning eval "Lightning.Release.migrate()"
```

### Configuring the Worker

By default, lightning starts the `worker` when running in `dev`. This can also
be configured using `RTM` env var. In case you don't want the hassle of
configuring the worker in `dev`, you can just remove/comment out the `worker`
service from the `docker-compose.yaml` file because lightning will start it for
you.

[Learn more about configuring workers](WORKERS.md)

### Using local adaptors

To run Lightning against your own checkout of the
[adaptors](https://github.com/openfn/adaptors) repo, see
[ADAPTORS.md](ADAPTORS.md).

### Caching the adaptor upstreams

For a record-and-replay proxy in front of npm, jsDelivr and GitHub while
developing, see `tooling/adaptor_cache/README.md`. The `ADAPTORS_NPM_*`
variables that point Lightning at it are described in
[ADAPTORS.md](ADAPTORS.md).

### Catching traces locally

Lightning exports OpenTelemetry traces over OTLP, so any local collector that
accepts OTLP will catch them. Jaeger all-in-one needs no configuration file and
has a query API that returns raw span JSON, which makes it a good default.

Write a compose file for it. `monitoring/` is ignored by git, so this stays out
of your commits:

```sh
mkdir -p monitoring
cat > monitoring/jaeger.yml <<'YAML'
services:
  jaeger:
    image: jaegertracing/jaeger:2.21.0
    container_name: lightning-jaeger
    environment:
      # OTLP ingest is opt-in on the 1.x all-in-one image.
      COLLECTOR_OTLP_ENABLED: "true"
    ports:
      - "16686:16686" # UI and query API
      - "4318:4318" # OTLP/HTTP
      - "4317:4317" # OTLP/gRPC
YAML
```

Start it and check it is listening. Spans are kept in memory only, so `down`
discards everything:

```sh
docker compose -f monitoring/jaeger.yml up -d
```

Wait approx 60 seconds for Jaeger to sample itself, then:

```sh
curl -s localhost:16686/api/v3/services
```

The reply is `{"services":["jaeger"]}`. Jaeger traces itself, so its own name
means the collector is up and nothing has arrived from Lightning yet.

Now start Lightning pointing at it, with sampling turned up:

```sh
TRACING_ENABLED=true \
  OTEL_TRACES_SAMPLER=always_on \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
  iex -S mix phx.server
```

Add `TRACING_ECTO_ENABLED=true` for a span per database query. See
[Tracing](DEPLOYMENT.md#tracing) for what each variable does.

Note that Lightning only processes the following OpenTelemetry ENV vars:

- `OTEL_SDK_DISABLED`
- `OTEL_EXPORTER_OTLP_ENDPOINT`
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`

The above can be configured via a `.env` file to be read by Dotenvy. Any other
`OTEL_*` env vars are read directly from the OS envrionment by the OpenTelemetry
libraries. As a result they will be ignored by Dotenvy, e.g.
`OTEL_TRACES_SAMPLER` in the `iex -S mix phx.server` code snippet above.

Generate some traffic, wait about ten seconds, then open http://localhost:16686
and pick the `lightning` service.

If you are not seeing an exepcted span, the following may be factors:

- The exporter batches, so the rule of thumb is that it may take 10-15 seconds
  for a span to arrive.
- Sampling keeps 5% of traces by default, unless you use the `always-on`
  sampler. This can be set with `OTEL_TRACES_SAMPLER=always_on`.

Jaeger keeps spans for the life of the container, and a service stays in the
list once it has appeared. Restart it between runs to reduce noise:

```sh
docker compose -f monitoring/jaeger.yml restart jaeger
```

You can also use the API to pull span data, as per this over-engineered example:

```sh
cat > monitoring/jaeger-attrs.sh <<'EOF'
#!/usr/bin/env bash
# Usage: ./jaeger-attrs.sh [service] [lookback_secs] [attribute_key]
set -euo pipefail

SERVICE="${1:-lightning}"
LOOKBACK_SECS="${2:-3600}"
ATTR_KEY="${3:-db.url}"
JAEGER_URL="${JAEGER_URL:-http://localhost:16686}"
OUT="${OUT:-/tmp/spans.json}"

START=$(jq -nr --argjson s "$LOOKBACK_SECS" 'now - $s | strftime("%Y-%m-%dT%H:%M:%SZ")')
END=$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%SZ")')

curl -fsSG "$JAEGER_URL/api/v3/traces" \
  --data-urlencode "query.service_name=$SERVICE" \
  --data-urlencode 'query.num_traces=200' \
  --data-urlencode "query.start_time_min=$START" \
  --data-urlencode "query.start_time_max=$END" \
  > "$OUT"

echo "== attribute keys (span + resource) =="
jq -r '.result.resourceSpans[]?
       | (.scopeSpans[]?.spans[]?.attributes[]?.key,
          .resource.attributes[]?.key)' \
  "$OUT" | sort -u

echo
echo "== values of $ATTR_KEY =="
jq -r --arg k "$ATTR_KEY" '.result.resourceSpans[]?.scopeSpans[]?.spans[]?.attributes[]?
       | select(.key == $k)
       | .value | to_entries[0].value
       | if type == "string" then . else tojson end' \
  "$OUT" | sort -u
EOF
chmod +x /monitoring/jaeger-attrs.sh
```

Unfortunately, there does not appear to be a human-friendly URL for Jaeger V3
API docs, but the OpenApi spec can be found
[here](https://raw.githubusercontent.com/jaegertracing/jaeger-idl/main/swagger/api_v3/query_service.openapi.yaml).

This can then be fed into a service such as the
[Swagger Petstore](https://petstore.swagger.io/?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjaegertracing%2Fjaeger-idl%2Fmain%2Fswagger%2Fapi_v3%2Fquery_service.openapi.yaml).

Stop the collector when you are done:

```sh
docker compose -f monitoring/jaeger.yml down
```

### Problems with Apple Silicon

You might run into some errors when running the docker containers on Apple
Silicon.
[We have documented the known ones here](README.md#problems-with-docker)
