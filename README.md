# OpenFn Lightning  [![CircleCI](https://circleci.com/gh/OpenFn/lightning/tree/main.svg?style=svg&circle-token=085c00fd6662e9a36012810fb7cf1f09f3604bc6)](https://circleci.com/gh/OpenFn/lightning/tree/main) [![codecov](https://codecov.io/gh/OpenFn/lightning/branch/main/graph/badge.svg?token=FfDMxdGL3a)](https://codecov.io/gh/OpenFn/lightning) [![Coverage Status](https://coveralls.io/repos/github/OpenFn/lightning/badge.svg?t=4vHZlQ)](https://coveralls.io/github/OpenFn/lightning)

## Setting up

### Postgres

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

### Elixir & Ecto

We use [asdf](https://github.com/asdf-vm/asdf) to help with our local environments.
Included in the repo is a `.tool-versions` file that is read by asdf in order
to dynamically make the specified versions of Elixir and Erlang available.

```sh
asdf install  # Install language versions
mix local.hex
mix deps.get
mix local.rebar --force
mix ecto.create # Create a development database in Postgres
mix ecto.migrate
```

### Run the app

Lightning is a web app. To run it, start the development server by running `mix phx.server`. 
Once the server has started, head to [`localhost:4000`](http://localhost:4000`) in your browser.

## Running Tests

Before the first time running the tests, you need a test database setup.

```sh
MIX_ENV=test mix ecto.create
```

And then after that run the tests using:

```sh
MIX_ENV=test mix test
```

We also have `test.watch` installed which can be used to rerun the tests on file changes.

## Security and Standards

We use a host of common Elixir static analysis tools to help us avoid common
pitfalls and make sure we keep everything clean and consistant.

In addition to our test suite, you can run the following commands:

* `mix format --check-formatted`  
  Code formatting checker, run again without the `--check-formatted` flag to 
  have your code automatically changed.
* `mix dialyzer`  
  Static analysis for type mismatches and other common warnings.
  See [dialyxir](https://github.com/jeremyjh/dialyxir)
* `mix credo`  
  Static analysis for consistancy, and coding standards.
  See [Credo](https://github.com/rrrene/credo).
* `mix sobelow --exit Medium`  
  Check for commonly known security exploits. See [Sobelow](https://sobelow.io/).
* `MIX_ENV=test mix coveralls`  
  Test coverage reporter. This command also runs the test suite, and can be 
  used in place of `mix test` when checking everything before pushing your code.
  See [excoveralls](https://github.com/parroty/excoveralls).

> For convenience there is a `verify` mix task that runs all of the above and
> defaults the `MIX_ENV` to `test`.

## Generating Documentation

You can generate the HTML and EPUB documentation locally using:

`mix docs` and opening `doc/index.html` in your browser.
