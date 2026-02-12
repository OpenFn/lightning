#!/usr/bin/env bash
# benchmarking/channels/run_all.sh
#
# Runs all channel proxy load test scenarios in sequence, logging output
# to a timestamped file. Assumes Lightning and mock sink are already running.
# Bails on first failure.
#
# Usage:
#   benchmarking/channels/run_all.sh [options]
#
# Options:
#   --sname NAME       Erlang short name (default: lt)
#   --cookie COOKIE    Erlang cookie (default: bench)
#   --duration SECS    Per-scenario duration (default: 30)
#   --concurrency N    Virtual users (default: 20)
#
# Examples:
#   benchmarking/channels/run_all.sh
#   benchmarking/channels/run_all.sh --duration 60 --concurrency 50
#   benchmarking/channels/run_all.sh --sname mynode --cookie mysecret

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────
SNAME="lt"
COOKIE="bench"
DURATION=30
CONCURRENCY=20

# ── Parse args ────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sname)      SNAME="$2";       shift 2 ;;
    --cookie)     COOKIE="$2";      shift 2 ;;
    --duration)   DURATION="$2";    shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,/^$/s/^# \?//p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── Log setup ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

TIMESTAMP="$(date +%Y.%m.%d-%H.%M)"
LOG="$RESULTS_DIR/$TIMESTAMP.log"
CSV="$RESULTS_DIR/$TIMESTAMP.csv"

# ── Preflight checks ─────────────────────────────────────────────
echo "=== Channel Proxy Load Test Suite ==="
echo ""
echo "  sname:       $SNAME"
echo "  cookie:      $COOKIE"
echo "  duration:    ${DURATION}s per scenario"
echo "  concurrency: $CONCURRENCY VUs"
echo "  log:         $LOG"
echo "  csv:         $CSV"
echo ""

echo -n "Checking mock sink at http://localhost:4001... "
if curl -sf http://localhost:4001/ > /dev/null 2>&1; then
  echo "ok"
else
  echo "FAILED"
  echo "error: Mock sink is not reachable at http://localhost:4001" >&2
  echo "Start it first: elixir benchmarking/channels/mock_sink.exs" >&2
  exit 1
fi

echo -n "Checking Lightning at http://localhost:4000... "
if curl -sf http://localhost:4000/ > /dev/null 2>&1; then
  echo "ok"
else
  echo "FAILED"
  echo "error: Lightning is not reachable at http://localhost:4000" >&2
  echo "Start it first: iex --sname lightning --cookie $COOKIE -S mix phx.server" >&2
  exit 1
fi

echo ""

# ── Scenario runner ───────────────────────────────────────────────
SCRIPT="benchmarking/channels/load_test.exs"
PASS=0
FAIL=0

run_scenario() {
  local name="$1"
  shift
  local extra_flags=("$@")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG"
  echo " Scenario: $name" | tee -a "$LOG"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG"

  local cmd=(
    elixir --sname "${SNAME}-${name}" --cookie "$COOKIE"
    "$SCRIPT"
    --scenario "$name"
    --concurrency "$CONCURRENCY"
    --duration "$DURATION"
    --csv "$CSV"
    "${extra_flags[@]}"
  )

  echo "  ${cmd[*]}" | tee -a "$LOG"
  echo "" | tee -a "$LOG"

  if "${cmd[@]}" 2>&1 | tee -a "$LOG"; then
    PASS=$((PASS + 1))
    echo "" | tee -a "$LOG"
  else
    FAIL=$((FAIL + 1))
    echo "" | tee -a "$LOG"
    echo "FATAL: scenario '$name' failed (exit $?). Stopping." | tee -a "$LOG"
    echo ""
    echo "Results so far: $PASS passed, $FAIL failed"
    echo "Log: $LOG"
    echo "CSV: $CSV"
    exit 1
  fi
}

# ── Run scenarios ─────────────────────────────────────────────────

# 1. Baseline — hit mock sink directly (no Lightning, no --sname)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG"
echo " Scenario: direct_sink" | tee -a "$LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG"

DIRECT_CMD=(
  elixir "$SCRIPT"
  --scenario direct_sink
  --concurrency "$CONCURRENCY"
  --duration "$DURATION"
  --csv "$CSV"
)
echo "  ${DIRECT_CMD[*]}" | tee -a "$LOG"
echo "" | tee -a "$LOG"

if "${DIRECT_CMD[@]}" 2>&1 | tee -a "$LOG"; then
  PASS=$((PASS + 1))
  echo "" | tee -a "$LOG"
else
  FAIL=$((FAIL + 1))
  echo "" | tee -a "$LOG"
  echo "FATAL: scenario 'direct_sink' failed. Stopping." | tee -a "$LOG"
  echo "Log: $LOG"
  exit 1
fi

# 2-7. Scenarios that go through Lightning
run_scenario happy_path
run_scenario ramp_up
run_scenario large_payload  --payload-size 1048576
run_scenario large_response --response-size 1048576
run_scenario mixed_methods
run_scenario slow_sink      --delay 2000

# ── Summary ───────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG"
echo " All scenarios complete: $PASS passed, $FAIL failed" | tee -a "$LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG"
echo ""
echo "Log: $LOG"
echo "CSV: $CSV"
