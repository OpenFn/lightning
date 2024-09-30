# Running Lightning Locally

This guide provides instructions for running Lightning locally, either by
installing dependencies on your machine or using Docker.

## By Installing Dependencies

### Setup

#### Postgres
Requires `postgres 15`.
When running in `dev` mode, the app will use the following credentials to authenticate:
- `PORT`: `5432`
- `USER`: `postgres`
- `PASSWORD`: `postgres`
- `DATABASE`: `lightning_dev`

This can however be overriden by specifying a `DATABASE_URL` env var.
e.g. `DATABASE_URL=postgresql://postgres:postgres@localhost:5432/lightning_dev`

We recommend that you use docker for running postgres as you'll get an exact version that we use:

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
asdf in order to dynamically make the specified versions of Elixir, Erlang and NodeJs
available. You'll need asdf plugins for
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
[[ $(uname -m) == 'arm64' ]] && mix compile.rambo # Force compile rambo if on M1
mix lightning.install_runtime
mix lightning.install_schemas
mix lightning.install_adaptor_icons
mix ecto.create
mix ecto.migrate
npm install --prefix assets
```

In case you encounter errors running any of these commands, see the [troubleshooting guide](README.md#troubleshooting) for
known errors.

### Running the App
To start the lightning server:

```sh
mix phx.server
```

Once the server has started, head to [`localhost:4000`](http://localhost:4000)
in your browser.

By default, the `worker` is started when run `mix phx.server` in `dev` mode. In case you
don't want to have your worker started in `dev`, set `RTM=false`:

```sh
RTM=false mix phx.server
```

## Using Docker

There is an existing `docker-compose.yaml` file in the project's root which has all the
services required. To start your services:

```sh
docker compose up
```

There 2 docker files in the root, `Dockerfile` builds the app in `prod` mode while `Dockerfile-dev`
runs it in `dev` mode. It is important to note that `mix commands` do not work in the `prod` images.

For exmaple, to run migrations in `dev` mode you run:

```sh
docker compose run --rm web mix ecto.migrate
```

While in `prod` mode:

```sh
docker compose run --rm web /app/bin/lightning eval "Lightning.Release.migrate()"
```

### Configuring the Worker

By default, lightning starts the `worker` when running in `dev`. This can also be configured using
`RTM` env var. In case you don't want the hassle of configuring the worker in `dev`, you can just
remove/comment out the `worker` service from the `docker-compose.yaml` file because lightning will
start it for you.

[Learn more about configuring workers](WORKERS.md)

### Problems with Apple Silicon

You might run into some errors when running the docker containers on Apple Silicon.
[We have documented the known ones here](README.md#problems-with-docker)
