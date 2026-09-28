#!/usr/bin/env bash
# Debian/Ubuntu platform support for bootstrap script
# Sourced by common.sh - do not execute directly

# Required system packages for native dependency compilation
REQUIRED_PACKAGES=(build-essential libsodium-dev cmake)
MISSING_PACKAGES=()

platform_check_dependencies() {
  for package in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -s "$package" &>/dev/null; then
      echo "  $package (installed)"
    else
      MISSING_PACKAGES+=("$package")
    fi
  done
}

platform_check_status() {
  local has_failures=false

  if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    {
      err "Missing system packages:"
      printf '   - %s\n' "${MISSING_PACKAGES[@]}"
      printf '%s\n' \
        "" \
        "To install, run:" \
        "  sudo apt-get update && sudo apt-get install -y ${MISSING_PACKAGES[*]}"
    } >&2
    has_failures=true
  fi

  if [[ "$has_failures" == true ]]; then
    {
      printf '%s\n' \
        "" \
        "Then re-run ./bin/bootstrap"
    } >&2
    exit 1
  fi

  ok "All dependencies are satisfied"
}

platform_install_dependencies() {
  # On Linux, we don't auto-install packages - we showed the command above
  # and exited. This function is only reached if all packages are installed.
  :
}

platform_setup_environment() {
  # Set compilers if not already set
  if [[ -z "${CC:-}" ]] && command -v gcc &>/dev/null; then
    CC="$(command -v gcc)"
    export CC
    echo "Set CC to $CC"
  fi

  if [[ -z "${CXX:-}" ]] && command -v g++ &>/dev/null; then
    CXX="$(command -v g++)"
    export CXX
    echo "Set CXX to $CXX"
  fi
}
