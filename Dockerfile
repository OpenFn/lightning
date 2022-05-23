# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian instead of
# Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20210902-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.13.2-erlang-24.2.1-debian-bullseye-20210902-slim
#
ARG ELIXIR_VERSION=1.13.1
ARG OTP_VERSION=24.2.1
ARG DEBIAN_VERSION=bullseye-20210902-slim
ARG NODE_VERSION=16

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="node:${NODE_VERSION}-slim"

FROM ${BUILDER_IMAGE} as builder

# install build and dev dependencies
RUN apt-get update -y && apt-get install -y \
  build-essential curl git inotify-tools

# isntall nodejs using nodesource
# https://github.com/nodesource/distributions/blob/master/README.md#deb
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
RUN apt-get install -y nodejs

RUN apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
RUN mix openfn.install.runtime

COPY lib lib
COPY bin bin
COPY assets assets

# compile assets
RUN mix assets.deploy

# Compile the release
COPY lib lib

RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

# isntall nodejs using nodesource
# https://github.com/nodesource/distributions/blob/master/README.md#deb
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales nodejs

RUN apt-get clean && rm -f /var/lib/apt/lists/*_**

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/lightning ./

USER nobody

CMD /app/bin/server