#!/usr/bin/env bash
# macOS (Darwin) platform support for bootstrap script
# Sourced by common.sh - do not execute directly

# Platform-specific state
HAS_HOMEBREW=""
HOMEBREW_PREFIX=""
HOMEBREW_PACKAGES_INSTALLED=""
MISSING_BREW_PACKAGES=()

platform_check_dependencies() {
  # Check Homebrew
  if command -v brew &>/dev/null; then
    HAS_HOMEBREW=true
    echo "  Homebrew: $(brew --version | head -1)"

    HOMEBREW_PREFIX="$(brew --prefix)"
    echo "     Using prefix: $HOMEBREW_PREFIX"

    HOMEBREW_PACKAGES_INSTALLED="$(brew list -1 2>/dev/null || true)"
  else
    HAS_HOMEBREW=false
    echo "  Homebrew: not installed"
  fi

  # Check required Homebrew packages
  if [[ "$HAS_HOMEBREW" == true ]]; then
    local required_brew_packages=(libsodium cmake)

    for package in "${required_brew_packages[@]}"; do
      if echo "$HOMEBREW_PACKAGES_INSTALLED" | grep -q "^$package$"; then
        echo "  $package (via Homebrew)"
      else
        MISSING_BREW_PACKAGES+=("$package")
      fi
    done
  fi

  # Check Xcode Command Line Tools
  if xcode-select -p &>/dev/null; then
    echo "  Xcode Command Line Tools: $(xcode-select -p)"
  else
    echo "  Xcode Command Line Tools not installed"
    MISSING_SYSTEM_DEPS+=("Xcode Command Line Tools")
  fi

  # Check C++ headers accessibility
  if echo '#include <cstddef>' | clang++ -x c++ -c - -o /dev/null &>/dev/null; then
    echo "  C++ standard library headers found"
  else
    {
      echo ""
      warn "C++ headers not accessible - this often requires reinstalling Command Line Tools"
      printf '%s\n' \
        "" \
        "   Try these solutions in order:" \
        "   1. Reset Xcode path: sudo xcode-select --reset" \
        "   2. If that doesn't work, completely reinstall CLT:" \
        "      sudo rm -rf /Library/Developer/CommandLineTools" \
        "      xcode-select --install" \
        "" \
        "   Note: The reinstall can take 10-15 minutes to download and install."
    } >&2
  fi
}

platform_check_status() {
  local has_installable_missing=false

  if [[ ${#MISSING_BREW_PACKAGES[@]} -gt 0 ]]; then
    if [[ "$HAS_HOMEBREW" == true ]]; then
      echo "Missing Homebrew packages (will install):"
      printf '   - %s\n' "${MISSING_BREW_PACKAGES[@]}"
      has_installable_missing=true
    else
      {
        err "Homebrew not available, cannot install:"
        printf '   - %s\n' "${MISSING_BREW_PACKAGES[@]}"
        printf '%s\n' \
          "" \
          "Please install Homebrew from https://brew.sh and re-run this script."
      } >&2
      exit 1
    fi
  fi

  if [[ "$has_installable_missing" == false ]]; then
    ok "All dependencies are satisfied"
  fi
}

platform_install_dependencies() {
  if [[ ${#MISSING_BREW_PACKAGES[@]} -gt 0 ]] && [[ "$HAS_HOMEBREW" == true ]]; then
    step "Installing missing Homebrew packages: ${MISSING_BREW_PACKAGES[*]}"
    if brew install "${MISSING_BREW_PACKAGES[@]}"; then
      ok "All missing packages have been installed"
      # Refresh the installed packages list
      HOMEBREW_PACKAGES_INSTALLED="$(brew list -1 2>/dev/null || true)"
    else
      err "Failed to install some packages"
      exit 1
    fi
    echo ""
  fi
}

platform_setup_tool_build_environment() {
  # Erlang's build only looks for `wx-config`, but Homebrew's wxwidgets@3.2
  # installs it as `wx-config-3.2`, so Erlang silently builds without wx
  # (and so without Observer).
  if ! command -v wx-config &>/dev/null && command -v wx-config-3.2 &>/dev/null; then
    WX_CONFIG_NAME="$(command -v wx-config-3.2)"
    export WX_CONFIG_NAME
    echo "Set WX_CONFIG_NAME to $WX_CONFIG_NAME"
  fi
}

platform_setup_environment() {
  if [[ -z "$HOMEBREW_PREFIX" ]] && command -v brew &>/dev/null; then
    HOMEBREW_PREFIX="$(brew --prefix)"
  fi

  # Explicitly set C/C++ compilers to avoid CMake detection issues
  if command -v clang &>/dev/null; then
    CC="$(command -v clang)"
    export CC
    echo "Set CC to $CC"
  fi

  if command -v clang++ &>/dev/null; then
    CXX="$(command -v clang++)"
    export CXX
    echo "Set CXX to $CXX"
  fi

  if echo "$HOMEBREW_PACKAGES_INSTALLED" | grep -q "^libsodium$" || brew list libsodium &>/dev/null; then
    export CPATH="$HOMEBREW_PREFIX/include"
    export LIBRARY_PATH="$HOMEBREW_PREFIX/lib"
    echo "Set environment variables for libsodium (using $HOMEBREW_PREFIX)"
  fi

  if command -v xcrun &>/dev/null; then
    local sdk_path
    sdk_path=$(xcrun --show-sdk-path 2>/dev/null || echo "")
    if [[ -n "$sdk_path" ]]; then
      export SDKROOT="$sdk_path"
      export CPATH="${CPATH:+$CPATH:}$SDKROOT/usr/include"
      echo "Set SDKROOT to $SDKROOT"
    fi
  fi
}
