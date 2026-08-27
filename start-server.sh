#!/usr/bin/env bash
# Local dev helper: start Lightning with the native-dep env vars this
# machine needs (libsodium headers + macOS SDK). Not for committing.
set -euo pipefail

SDKROOT="$(xcrun --show-sdk-path)"
export SDKROOT
export CPATH="/opt/homebrew/include:$SDKROOT/usr/include"
export LIBRARY_PATH="/opt/homebrew/lib"

exec mix phx.server
