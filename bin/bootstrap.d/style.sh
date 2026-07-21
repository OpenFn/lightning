#!/usr/bin/env bash
# Terminal styling helpers shared across the bin/ scripts.
# Sourced, not executed. Safe to source more than once.
#
# Colour is emitted only when stdout is a terminal and NO_COLOR is unset or
# empty (https://no-color.org/), so piped or redirected output stays plain.
# The palette variables hold real escape bytes (via $'...'), so they work with
# plain echo/printf '%s' and interpolate cleanly inside an unquoted heredoc.

# These are a palette for sourcing scripts; some are used only by consumers.
# shellcheck disable=SC2034
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
else
  BOLD="" RESET="" RED="" GREEN="" YELLOW="" CYAN=""
fi

# step: bold "==> Heading" for section boundaries in noisy output.
step() { printf '%s==>%s %s%s%s\n' "$BOLD" "$RESET" "$BOLD" "$*" "$RESET"; }

# ok: green success line.
ok() { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }

# warn: yellow advisory, to stderr.
warn() { printf '%sWarning:%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }

# err: red failure line, to stderr. The caller is responsible for exiting.
# stderr shares the terminal with stdout for these interactive tools, so the
# -t 1 guard above governs it too rather than a separate -t 2 check.
err() { printf '%sError:%s %s\n' "$RED" "$RESET" "$*" >&2; }
