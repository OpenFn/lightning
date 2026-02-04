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

  # Check for Rust (optional but recommended for Rambo)
  if command -v rustc &>/dev/null; then
    echo "  Rust: $(rustc --version)"
  else
    echo "  Rust: not installed (optional)"
  fi
}

platform_check_status() {
  if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo "Missing system packages:"
    for package in "${MISSING_PACKAGES[@]}"; do
      echo "   - $package"
    done
    echo ""
    echo "To install, run:"
    echo "  sudo apt-get update && sudo apt-get install -y ${MISSING_PACKAGES[*]}"
    echo ""
    echo "Then re-run ./bin/bootstrap"
    exit 1
  fi

  echo "All dependencies are satisfied"
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

platform_post_compile_hooks() {
  # No platform-specific post-compile hooks needed on Linux
  # Rambo compiles automatically during mix deps.compile
  :
}
