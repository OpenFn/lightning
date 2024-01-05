# OpenFn/Lightning [![CircleCI](https://dl.circleci.com/status-badge/img/gh/OpenFn/Lightning/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/OpenFn/Lightning/tree/main) [![codecov](https://codecov.io/gh/OpenFn/Lightning/branch/main/graph/badge.svg?token=FfDMxdGL3a)](https://codecov.io/gh/OpenFn/Lightning) ![Docker Pulls](https://img.shields.io/docker/pulls/openfn/lightning)

OpenFn/Lightning is a fully open source, workflow automation platform that's
used to automate critical business processes and integrate information systems.
From last-mile services to national-level reporting, it boosts efficiency &
effectiveness while enabling secure, stable, scalable interoperability at all
levels. **Read more about Lightning
[on OpenFn/Docs](https://docs.openfn.org/documentation/about-lightning).**

Lightning is the latest "v2" of OpenFn, the
[Digital Public Good for workflow automation](https://app.digitalpublicgoods.net/a/10176).
Use Lightning to visually build, execute and manage workflows.

- The latest version of the OpenFn technology - first launched in 2014, now
  tried and tested by NGOs in over 40 countries
- Fully open source (no premium features or community edition, you get the same
  product whether using SaaS or self-hosted)
- Recognised as a Digital Public Good by the
  [DPGA](https://digitalpublicgoods.net/) and a Global Good for Health by
  [Digital Square](https://digitalsquare.org/digital-health-global-goods)

## Contents

- [Demo](#demo)
- [Use OpenFn Online](#use-openfn-online)
- [Features](#features)
- [Getting started](#getting-started)
  - [Run Lightning via Docker](#run-via-docker)
  - [Deploy Lightning on Docker or Kubernetes](#deploy-on-external-infrastructure)
  - [Run Lightning on your local machine (contributors)](#run-lightning-locally)
  - [Troubleshooting](#troubleshooting)
  - [Contribute](#contribute-to-this-project)
  - [Project Configuration Quickstart](#project-configuration-quickstart)
- [Generate the documentation](#generating-documentation)
- [Security and standards](#security-and-standards)
- [Server specs for self-hosting](#server-specs-for-self-hosting)
- [Questions or feedback?](#support)

![Screenshot 2023-03-15 at 13 01 13](https://user-images.githubusercontent.com/36554605/225275565-99c94f3b-3057-4185-9086-58015c28e77f.png)

## Demo

Watch a quick demo here: https://www.youtube.com/watch?v=BNaxlHAWb5I

Explore our [demo app\*](https://demo.openfn.org/) with username:
`demo@openfn.org`, password: `welcome123`, or read through the
[features](#features) section to view screenshots of the app.

_\*Note that the demo app refreshes daily, so do not configure workflows you
want to save._

## Use OpenFn Online

Register for an account at [app.openfn.org](https://app.openfn.org/) and go
through the
[quick-start guide](https://docs.openfn.org/documentation/build/lightning-quick-start)
to get familiar with the app.

## Features

### Build

Plan and build workflows using Lightning's visual interface to quickly define
when, where and what you want your automation to do.

<img width="1679" alt="image" src="https://github.com/OpenFn/Lightning/assets/8732845/15afafe7-561b-4d79-9cd8-5d31506a9031">

Use our
[CLI](https://github.com/OpenFn/kit/blob/main/packages/cli/README.md#openfncli)
to quickly build, edit and deploy projects from the comfort of your own code
editor.

### Monitor

Monitor all workflow activity in one place.

<img width="1680" alt="image" src="https://github.com/OpenFn/Lightning/assets/8732845/909dba85-e0d1-4bce-8a17-5949386c6375">

- Filter and search runs to identify issues that need addressing and follow how
  a specific request has been processed
- Configure alerts to be notified on run failures
- Receive a project digest for a daily/weekly/monthly summary of your project
  activity

### Manage

Manage users and access by project
![Screenshot 2023-03-21 at 10 09 03](https://user-images.githubusercontent.com/36554605/226538682-e7f43407-2363-41eb-bee8-73307e7f3cf3.png)

### Roles and permissions

Authorization is a central part of Lightning. As such, users are given different
roles which determine what level of access they have for resources in the
application. For more details about roles and permissions in Lightning, please
refer to our
[documentation](https://docs.openfn.org/documentation/about-lightning#roles-and-permissions).

### Roadmap

View our public roadmap
[here](https://docs.openfn.org/documentation/openfn-roadmap#lightning-roadmap).

## Getting Started

- If you only want to [_**RUN**_](#run-via-docker) Lightning on your own server,
  we recommend using Docker.
- If you want to [_**DEPLOY**_](#deploy-on-external-infrastructure) Lightning,
  we recommend Docker builds and Kubernetes.
- If you want to [_**CONTRIBUTE**_](#contribute-to-this-project) to the project,
  we recommend
  [running Lightning on your local machine](#run-lightning-locally).

## **Run** via Docker

1. Install the latest version of
   [Docker](https://docs.docker.com/engine/install/)
2. Clone [this repo](https://github.com/OpenFn/Lightning) using git
3. Copy the `.env.example` file to `.env`
4. Run `docker compose run --rm web mix ecto.migrate`

By default the application will be running at
[localhost:4000](http://localhost:4000/).

You can then rebuild and run with `docker compose build` and
`docker compose up`. See ["Problems with Docker"](#problems-with-docker) for
additional troubleshooting help. Note that you can also create your own
`docker-compose.yml` file, configuring a postgres database and using a
[pre-built image](https://hub.docker.com/repository/docker/openfn/lightning)
from Dockerhub.

## **Deploy** on external infrastructure

Head to the [Deploy](https://docs.openfn.org/documentation/deploy/options)
section of our docs site to get started.

For technical guidelines, see [deployment considerations](DEPLOYMENT.md) for
more detailed information.

## Run Lightning locally

### Clone the repo and optionally set ENVs

```sh
git clone git@github.com:OpenFn/Lightning.git # or from YOUR fork!
cd Lightning
cp .env.example .env # and adjust as necessary!
```

Take note of database names and ports in particular—they've got to match across
your Postgres setup and your ENVs. You can run lightning without any ENVs
assuming a vanilla postgres setup (see below), but you may want to make
adjustments.

### Database Setup

If you're already using Postgres locally, create a new database called
`lightning_dev`, for example.

If you'd rather use Docker to set up a Postgres DB, create a new volume and
image:

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

### Elixir & Ecto Setup

We use [asdf](https://github.com/asdf-vm/asdf) to configure our local
environments. Included in the repo is a `.tool-versions` file that is read by
asdf in order to dynamically make the specified versions of Elixir and Erlang
available. You'll need asdf plugins for
[Erlang](https://github.com/asdf-vm/asdf-erlang),
[NodeJs](https://github.com/asdf-vm/asdf-nodejs)
[Elixir](https://github.com/asdf-vm/asdf-elixir) and
[k6](https://github.com/grimoh/asdf-k6).

```sh
asdf install  # Install language versions
mix local.hex
mix deps.get
mix local.rebar --force
mix ecto.create # Create a development database in Postgres
mix ecto.migrate
[[ $(uname -m) == 'arm64' ]] && mix compile.rambo # Force compile rambo if on M1
mix lightning.install_runtime
mix lightning.install_schemas
mix lightning.install_adaptor_icons
npm install --prefix assets
```

### Run the app

Lightning is a web app. To run it in interactive Elixir mode, start the
development server by running with your environment variables by running:

```sh
iex -S mix phx.server
```

or if you have set up custom environment variables, run:

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

## Benchmarking

We are using [k6](https://k6.io/) to benchmark Lightning. Under `benchmarking`
folder you can find a script for benchmarking Webhook Workflows.

See [Benchmarking](benchmarking/README.md) for more detailed information.

## Troubleshooting

### Trouble with environment variables

For troubleshooting custom environment variable configuration it's important to
know how an Elixir app loads and modifies configuration. The order is as
follows:

1. Stuff in `config.exs` is loaded.
2. _That_ is then modified (think: _overwritten_) by stuff your ENV-specific
   config: `dev.exs`, `prod.exs` or `test.exs`.
3. _That_ is then modified by `runtime.exs` which is where you are allowed to
   use `System.env()`
4. _Finally_ `init/2` (if present in a child application) gets called (which
   takes the config which has been set in steps 1-3) when that child application
   is started during the parent app startup defined in `application.ex`.

### Problems with Postgres

If you're having connecting issues with Postgres, check the database section of
your `.env` to ensure the DB url is correctly set for your environment — note
that composing a DB url out of other, earlier declared variables, does not work
while using `xargs`.

### Problems with Debian

If you're getting this error on debian

```
==> earmark_parser
Compiling 1 file (.yrl)
/usr/lib/erlang/lib/parsetools-2.3.1/include/yeccpre.hrl: no such file or directory
could not compile dependency :earmark_parser, "mix compile" failed. You can recompile this dependency with "mix deps.compile earmark_parser", update it with "mix deps.update earmark_parser" or clean it with "mix deps.clean earmark_parser"
```

You need to install erlang development environment `sudo apt install erlang-dev`
[refer to this issue](https://github.com/elixir-lang/ex_doc/issues/1441)

### Problems with Docker

#### Versions

The build may not work on old versions of Docker and Docker compose. It has been
tested against:

```
Docker version 20.10.17, build 100c701
Docker Compose version v2.6.0
```

### Problems with `rambo`

When running `mix compile.rambo` on Apple Silicon (an Apple M1/M2, `macarm`,
`aarch64-apple-darwin`) and encountering the following error:

```
** (RuntimeError) Rambo does not ship with binaries for your environment.

    aarch64-apple-darwin22.3.0 detected

Install the Rust compiler so a binary can be prepared for you.

    lib/mix/tasks/compile.rambo.ex:89: Mix.Tasks.Compile.Rambo.compile!/0
    lib/mix/tasks/compile.rambo.ex:51: Mix.Tasks.Compile.Rambo.run/1
    (mix 1.14.2) lib/mix/task.ex:421: anonymous fn/3 in Mix.Task.run_task/4
    (mix 1.14.2) lib/mix/cli.ex:84: Mix.CLI.run_task/2
```

You can resolve this error by installing the Rust compiler using Homebrew. Run
the following command in your terminal: `brew install rust`

If you have already compiled Rambo explicitly via `mix compile.rambo`, and you
are still seeing the following error:

```
sh: /path_to_directory/Lightning/_build/dev/lib/rambo/priv/rambo: No such file or directory
sh: line 0: exec: /path_to_directory/Lightning/_build/dev/lib/rambo/priv/rambo: cannot execute: No such file or directory
```

You can try renaming `deps/rambo/priv/rambo-mac` to `deps/rambo/priv/rambo`.

If neither of the approaches above work, please raise an issue.

#### Starting from scratch

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

## Project Configuration Quickstart

For help getting started with your OpenFn/Lightning Project and Workflows
configuration, check out the
[Lightning Quickstart Guidance](https://docs.openfn.org/documentation/build/lightning-quick-start)
on OpenFn/Docs.

## **Contribute** to this project

First, thanks for being here! You're contributing to a digital public good that
will always be free and open source and aimed at serving innovative NGOs,
governments, and social impact organizations the world over! You rock. ❤️

FYI, Lightning is built in [Elixir](https://elixir-lang.org/), harnessing the
[Phoenix Framework](https://www.phoenixframework.org/). Currently, the only
unbundled dependency is a [PostgreSQL](https://www.postgresql.org/) database.

If you'd like to contribute to this projects, follow the steps below:

### Assign yourself to an issue

Read through the existing [issues](https://github.com/OpenFn/Lightning/issues),
assign yourself to the issue you have chosen. Leave a comment on the issue to
let us know you'll be working on it, and if you have any questions of
clarifications that would help you get started ask them there - we will get back
to you as soon as possible.

If there isn't already an issue for the feature you would like to contribute,
please start a discussion in our
[community forum](https://community.openfn.org/c/feature-requests/12).

### Open a pull request

1. Clone the Lightning repository, then
   [fork it](https://docs.github.com/en/get-started/quickstart/fork-a-repo).

2. Run through [setting up your environment](#set-up-your-environment) and make
   your changes.

3. Make sure you have written your tests and updated /CHANGELOG.md (in the
   'Unreleased' section, add a short description of the changes you are making,
   along with a link to your issue).

4. Open a draft pull request by clicking "Contribute > Open Pull Request" from
   your forked repository. Fill out the pull request template (this will be
   added automatically for you), then make sure to self-review your code and go
   through the 'Review checklist'. Don't worry about the QA checkbox, our
   product manager Amber will tick that once she has reviewed your PR. You can
   leave any notes for the reviewer in a comment.

5. Once you're ready to submit a pull request, you can mark your draft PR as
   'Ready for review' and assign @stuartc or @taylordowns2000.

## Generating Documentation

You can generate the HTML and EPUB documentation locally using:

`mix docs` and opening `doc/index.html` in your browser.

## Security and Standards

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

For more guidance on security best practices for workflow automation
implementations, check out OpenFn Docs:
[docs.openfn.org/documentation/getting-started/security](https://docs.openfn.org/documentation/getting-started/security)

## Server Specs for Self-Hosting

For recommend server specifications for self-hosting of Lightning, check out
this Community topic:
[community.openfn.org/t/specs-for-self-hosting-lightning/292](https://community.openfn.org/t/specs-for-self-hosting-lightning/292)

## Support

If you have any questions, feedback, or issues, please:

- Post on the OpenFn Community at
  [community.openfn.org](https://community.openfn.org)
- Open an issue directly on this Github Repo:
  [github.com/OpenFn/Lightning/issues](https://github.com/OpenFn/Lightning/issues)
