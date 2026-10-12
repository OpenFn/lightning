#!/usr/bin/env bash
# Get a local Lightning running with the same data as demo.openfn.org, from a
# bare Claude Code cloud container (Ubuntu 24.04). Idempotent: re-running skips
# whatever is already done.
#
#   .claude/skills/screenshots/setup.sh            # setup + seed + start server
#   .claude/skills/screenshots/setup.sh --reseed   # also wipe and re-seed demo data
#
# Prints the demo project/workflow ids at the end for use with shoot.mjs.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
LOG_DIR="${LOG_DIR:-/tmp/lightning-screenshots}"
mkdir -p "$LOG_DIR"
PORT="${PORT:-4000}"
RESEED=false
[[ "${1:-}" == "--reseed" ]] && RESEED=true

step() { printf '\n==> %s\n' "$*"; }

# 1. Erlang + Elixir at the .tool-versions versions. Ubuntu's apt packages are
#    far too old; hex.pm publishes prebuilt OTP for ubuntu-24.04 and Elixir zips.
OTP_VSN=$(awk '/^erlang /{print $2}' .tool-versions)
EX_VSN=$(awk '/^elixir /{print $2}' .tool-versions)     # e.g. 1.18.4-otp-28
BEAM=/opt/beam
if ! command -v elixir >/dev/null 2>&1 && [[ ! -x $BEAM/elixir/bin/elixir ]]; then
  step "Installing Erlang/OTP $OTP_VSN and Elixir $EX_VSN from builds.hex.pm"
  mkdir -p $BEAM/otp-src
  curl -sSfL "https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/OTP-${OTP_VSN}.tar.gz" \
    | tar xz -C $BEAM/otp-src --strip-components=1
  (cd $BEAM/otp-src && ./Install -minimal $BEAM/otp >/dev/null)
  curl -sSfL -o $BEAM/ex.zip "https://builds.hex.pm/builds/elixir/v${EX_VSN}.zip"
  mkdir -p $BEAM/elixir && unzip -qo $BEAM/ex.zip -d $BEAM/elixir
fi
export PATH=$BEAM/otp/bin:$BEAM/elixir/bin:$PATH
export LANG=C.UTF-8 ELIXIR_ERL_OPTIONS=+fnu MIX_ENV=dev

# 2. Native build deps. enacl needs sodium.h; the rest are what bin/bootstrap
#    checks for on Debian.
missing=()
for p in build-essential libsodium-dev cmake inotify-tools; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if ((${#missing[@]})); then
  step "apt-get install ${missing[*]}"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >/dev/null
fi

# 3. Postgres 16 is installed but stopped; dev config expects postgres:postgres.
if ! pg_isready -q -h localhost; then
  step "Starting Postgres"
  pg_ctlcluster 16 main start
  su postgres -c "psql -qc \"ALTER USER postgres PASSWORD 'postgres';\""
fi

# 4. Deps, compile, JS deps, esbuild/tailwind binaries, worker runtime.
step "Compiling (first run takes several minutes; log: $LOG_DIR/build.log)"
{
  mix local.hex --force --if-missing
  mix local.rebar --force --if-missing
  mix deps.get
  mix compile
  [[ -d assets/node_modules ]] || npm install --prefix assets --no-audit --no-fund
  mix assets.setup
  mix lightning.install_runtime
} >"$LOG_DIR/build.log" 2>&1 || { tail -30 "$LOG_DIR/build.log"; exit 1; }

# 5. Database + demo data. This is exactly what demo.openfn.org runs nightly:
#    priv/repo/demo.exs -> Lightning.Demo.reset_demo/0, which only acts when
#    IS_RESETTABLE_DEMO is set, wipes everything, then SetupUtils.setup_demo.
step "Migrating lightning_dev"
mix ecto.create --quiet >/dev/null 2>&1 || true
mix ecto.migrate >"$LOG_DIR/migrate.log" 2>&1
DB=postgres://postgres:postgres@localhost/lightning_dev
if $RESEED || [[ "$(psql "$DB" -Atc 'select count(*) from users')" == "0" ]]; then
  step "Seeding demo data (priv/repo/demo.exs)"
  IS_RESETTABLE_DEMO=yes mix run priv/repo/demo.exs >"$LOG_DIR/seed.log" 2>&1
fi

# 6. Server.
if curl -sf -o /dev/null "http://localhost:$PORT/users/log_in"; then
  step "Server already up on :$PORT"
else
  step "Starting mix phx.server on :$PORT (log: $LOG_DIR/server.log)"
  PORT=$PORT nohup mix phx.server >"$LOG_DIR/server.log" 2>&1 &
  timeout 300 bash -c "until curl -sf -o /dev/null http://localhost:$PORT/users/log_in; do sleep 2; done"
fi

step "Ready: http://localhost:$PORT  (password for every user: welcome12345)"
psql "$DB" -Atc "select '  user      '||email from users order by email"
psql "$DB" -Atc "select '  project   '||name||'  '||id from projects order by name"
psql "$DB" -Atc "select '  workflow  '||w.name||'  /projects/'||w.project_id||'/w/'||w.id from workflows w order by w.name"
