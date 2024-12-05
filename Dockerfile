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

ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.1.2
ARG DEBIAN_VERSION=bookworm-20241202
ARG NODE_VERSION=18.17.1

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder
ARG NODE_VERSION

# install build and dev dependencies
RUN apt-get update -y && apt-get install -y \
    build-essential curl git inotify-tools libsodium-dev

COPY bin/install_node bin/install_node
RUN bin/install_node ${NODE_VERSION}

RUN apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

COPY mix.* ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

RUN mix lightning.install_runtime

RUN mix lightning.install_adaptor_icons

RUN mix lightning.install_schemas

COPY assets assets
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

ARG BRANCH=""
ARG COMMIT=""
ARG IMAGE_TAG=""
LABEL branch=${BRANCH}
LABEL commit=${COMMIT}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 \
  locales curl gpg libsodium-dev

RUN apt-get clean && rm -f /var/lib/apt/lists/*_**

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

COPY bin/install_node tmp/install_node
RUN tmp/install_node ${NODE_VERSION}

WORKDIR "/app"

RUN useradd --uid 1000 --home /app lightning
RUN chown lightning /app

# set runner ENV
ENV MIX_ENV="prod"
ENV ADAPTORS_PATH /app/priv/openfn

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

CMD /app/bin/server
