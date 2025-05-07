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
#   - Ex: hexpm/elixir:1.16.2-erlang-26.2.5-debian-bookworm-20240513
#
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3.3
ARG DEBIAN_VERSION=bookworm-20250428
ARG NODE_VERSION=22.12.0
ARG ERL_FLAGS

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder
ARG NODE_VERSION
ARG ERL_FLAGS

# install build and dev dependencies
RUN apt-get update -y && apt-get install -y --no-install-recommends \
  build-essential curl git inotify-tools openssl ca-certificates \
  libsodium-dev

# Install Node.js from NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION%%.*}.x | bash - && \
  apt-get install -y nodejs=${NODE_VERSION}-1nodesource1

RUN apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"
ENV ERL_FLAGS=${ERL_FLAGS}

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile
RUN mix assets.setup

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix lightning.install_runtime
RUN mix lightning.install_adaptor_icons
RUN mix lightning.install_schemas
RUN npm install --prefix assets

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# ------------------------------------------------------------------------------
# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}
ARG NODE_VERSION
ARG ERL_FLAGS

ARG BRANCH=""
ARG COMMIT=""
ARG IMAGE_TAG=""
LABEL branch=${BRANCH}
LABEL commit=${COMMIT}

RUN apt-get update -y && apt-get install -y --no-install-recommends \
  libstdc++6 openssl libncurses5 locales ca-certificates \
  curl libsodium-dev

RUN apt-get clean && rm -f /var/lib/apt/lists/*_**

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"

# Install Node.js from NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION%%.*}.x | bash - && \
  apt-get install -y nodejs=${NODE_VERSION}-1nodesource1

RUN useradd --uid 1000 --home /app lightning
RUN chown lightning /app

# set runner ENV
ENV MIX_ENV="prod"
ENV ERL_FLAGS=${ERL_FLAGS}
ENV ADAPTORS_PATH=/app/priv/openfn

# Only copy the final release and the adaptor directory from the build stage
COPY --from=builder --chown=lightning:root /app/_build/${MIX_ENV}/rel/lightning ./
COPY --from=builder --chown=lightning:root /app/priv/openfn ./priv/openfn
COPY --from=builder --chown=lightning:root /app/priv/schemas ./priv/schemas
COPY --from=builder --chown=lightning:root /app/priv/github ./priv/github

USER lightning

ENV SCHEMAS_PATH="/app/priv/schemas"
ENV COMMIT=${COMMIT}
ENV BRANCH=${BRANCH}
ENV IMAGE_TAG=${IMAGE_TAG}

CMD ["/app/bin/server"]
