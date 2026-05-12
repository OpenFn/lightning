#!/usr/bin/env bash
# Debian/Ubuntu platform support for bootstrap script
# Sourced by common.sh - do not execute directly

# Required system packages for native dependency compilation
REQUIRED_PACKAGES=(build-essential libsodium-dev cmake)
MISSING_PACKAGES=()
MISSING_RUST=false

# Rambo ships precompiled binaries only for x86_64 mac/linux/windows.
# Other architectures (e.g. aarch64/arm64) must build from source via cargo.
rust_required_for_arch() {
  case "$(uname -m)" in
  aarch64 | arm64) return 0 ;;
  *) return 1 ;;
  esac
}

platform_check_dependencies() {
  for package in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -s "$package" &>/dev/null; then
      echo "  $package (installed)"
    else
      MISSING_PACKAGES+=("$package")
    fi
  done

  if command -v rustc &>/dev/null; then
    echo "  Rust: $(rustc --version)"
  elif rust_required_for_arch; then
    echo "  Rust: not installed (required on $(uname -m) — rambo has no precompiled binary)"
    MISSING_RUST=true
  else
    echo "  Rust: not installed (optional)"
  fi
}

platform_check_status() {
  local has_failures=false

  if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo "Missing system packages:"
    for package in "${MISSING_PACKAGES[@]}"; do
      echo "   - $package"
    done
    echo ""
    echo "To install, run:"
    echo "  sudo apt-get update && sudo apt-get install -y ${MISSING_PACKAGES[*]}"
    has_failures=true
  fi

  if [[ "$MISSING_RUST" == true ]]; then
    [[ "$has_failures" == true ]] && echo ""
    echo "Missing Rust toolchain (rambo has no precompiled binary for $(uname -m))"
    echo ""
    echo "Install via rustup (recommended):"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo ""
    echo "Or via apt:"
    echo "  sudo apt-get install -y rustc cargo"
    has_failures=true
  fi

  if [[ "$has_failures" == true ]]; then
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
  # On architectures without a precompiled rambo binary (e.g. aarch64),
  # the `:rambo` compiler builds priv/rambo via cargo. If the binary is
  # missing — typically because an earlier bootstrap ran before Rust was
  # installed and mix has since cached rambo as "compiled" — force a
  # rebuild so the rest of bootstrap can actually invoke it.
  if ! rust_required_for_arch; then
    return
  fi

  local rambo_bin="_build/${MIX_ENV:-dev}/lib/rambo/priv/rambo"
  if [[ -x "$rambo_bin" ]]; then
    return
  fi

  echo "Rambo binary missing at $rambo_bin — building via cargo..."
  (cd deps/rambo && mix compile.rambo)
}
