# OpenFn/Lightning (alpha) [![CircleCI](https://circleci.com/gh/OpenFn/Lightning/tree/main.svg?style=svg&circle-token=085c00fd6662e9a36012810fb7cf1f09f3604bc6)](https://circleci.com/gh/OpenFn/Lightning/tree/main) [![codecov](https://codecov.io/gh/OpenFn/Lightning/branch/main/graph/badge.svg?token=FfDMxdGL3a)](https://codecov.io/gh/OpenFn/Lightning) ![Docker Pulls](https://img.shields.io/docker/pulls/openfn/lightning)

Lightning extends the existing [OpenFn](https://www.openfn.org) Digital Public
Good, providing a web UI to visually manage complex workflow automation
projects. Learn more about OpenFn at [docs.openfn.org](https://docs.openfn.org).

## Getting Started

- If you only want to [_**RUN**_](#run-via-docker) Lightning on your own server,
  we recommend using Docker.
- If you want to [_**DEPLOY**_](#deploy-on-external-infrastructure) Lightning,
  we recommend Docker builds and Kubernetes.
- If you want to [_**CONTRIBUTE**_](#contribute-to-this-project) to the project,
  we recommend setting up Elixir on your local machine.

## **Run** via Docker

1. Install [Docker](https://docs.docker.com/engine/install/)
2. Clone the repo using git
3. Copy the `.env.example` file to `.env`
4. Run docker compose with either a
   [pre-built image](https://hub.docker.com/repository/docker/openfn/lightning)
   or building your own.

| Option    | Command                                                                    |
| --------- | -------------------------------------------------------------------------- |
| Pre-built | `docker compose run --rm web mix ecto.migrate`                             |
| BYO       | `docker compose run -f docker-compose.build.yml --rm web mix ecto.migrate` |

Once you've done that, run `docker compose up` every time you want to start up
the server.

By default the application will be running at
[localhost:4000](http://localhost:4000/).

See ["Problems with Docker"](#problems-with-docker) for additional
troubleshooting help.

## **Deploy** on external infrastructure

See [Deployment](DEPLOYMENT.md) for more detailed information.

## **Contribute** to this project

Lightning is built in [Elixir](https://elixir-lang.org/), harnessing the
[Phoenix Framework](https://www.phoenixframework.org/). Currently, the only
unbundled dependency is a [PostgreSQL](https://www.postgresql.org/) database.

### Set up your environment

#### Clone the repo and set ENVs

```sh
git clone git@github.com:OpenFn/Lightning.git
cd Lightning
cp .env.example .env # and adjust as necessary!
```

Take note of database names and ports in particular—they've got to match across
your Postgres setup and your ENVs.

#### Database Setup

**If you're already using Postgres**, run `createdb lightning_dev` to create a
new database for use with Lightning.

**If you'd rather use Docker** to set up a Postgres DB, create a new volume and
image:

```sh
docker volume create lightning-postgres-data

docker create \
  --name lightning-postgres \
  --mount source=lightning-postgres-data,target=/var/lib/postgresql/data \
  --publish 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  postgres:14.1-alpine

docker start lightning-postgres
```

#### Elixir & Ecto Setup

We use [asdf](https://github.com/asdf-vm/asdf) to configure our local
environments. Included in the repo is a `.tool-versions` file that is read by
asdf in order to dynamically make the specified versions of Elixir and Erlang
available.

```sh
asdf install  # Install language versions
mix local.hex
mix deps.get
mix local.rebar --force
mix ecto.create # Create a development database in Postgres
mix ecto.migrate
mix openfn.install.runtime
```

### Run the app

Lightning is a web app. To run it in interactive Elixir mode, start the
development server by running with your environment variables by running:

```sh
env $(cat .env | grep -v "#" | xargs ) iex -S mix phx.server
```

Once the server has started, head to [`localhost:4000`](http://localhost:4000)
in your browser.

### Run the tests

Before the first time running the tests, you need a test database setup.

```sh
MIX_ENV=test mix ecto.create
```

And then after that run the tests using:

```sh
MIX_ENV=test mix test
```

We also have `test.watch` installed which can be used to rerun the tests on file
changes.

### Security and Standards

We use a host of common Elixir static analysis tools to help us avoid common
pitfalls and make sure we keep everything clean and consistent.

In addition to our test suite, you can run the following commands:

- `mix format --check-formatted`  
  Code formatting checker, run again without the `--check-formatted` flag to
  have your code automatically changed.
- `mix dialyzer`  
  Static analysis for type mismatches and other common warnings. See
  [dialyxir](https://github.com/jeremyjh/dialyxir).
- `mix credo`  
  Static analysis for consistency, and coding standards. See
  [Credo](https://github.com/rrrene/credo).
- `mix sobelow`  
  Check for commonly known security exploits. See
  [Sobelow](https://sobelow.io/).
- `MIX_ENV=test mix coveralls`  
  Test coverage reporter. This command also runs the test suite, and can be used
  in place of `mix test` when checking everything before pushing your code. See
  [excoveralls](https://github.com/parroty/excoveralls).

> For convenience there is a `verify` mix task that runs all of the above and
> defaults the `MIX_ENV` to `test`.

### Generating Documentation

You can generate the HTML and EPUB documentation locally using:

`mix docs` and opening `doc/index.html` in your browser.

## Troubleshooting

### Problems with Docker

If you're actively working with docker, you start experiencing issues, and you
would like to start from scratch you can clean up everything and start over like
this:

```sh
# To remove any ignored files and reset your .env to it's example
git clean -fdx && cp .env.example .env
# You can skip the line below if you want to keep your database
docker compose down --rmi all --volumes

docker compose build --no-cache web && \
  docker compose create --force-recreate

docker compose run --rm web mix ecto.migrate
docker compose up
```
