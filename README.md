OpenFn Lighting
===============

Setting up
----------

### Postgres

```
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

```
asdf install  # Install language versions
mix local.hex
mix local.rebar --force
mix ecto.create # Create a development database in Postgres
```

Running Tests
-------------

Before the first time running the tests, you need a test database setup.

```
MIX_ENV=test mix ecto.create
```

And then after that run the tests using:

```
MIX_ENV=test mix test
```
