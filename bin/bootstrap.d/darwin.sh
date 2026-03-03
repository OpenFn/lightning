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

  # Check Rust
  if command -v rustc &>/dev/null; then
    echo "  Rust: $(rustc --version)"
  else
    MISSING_BREW_PACKAGES+=("rust")
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

    # Check if Rust is available via Homebrew even if not in PATH
    if ! command -v rustc &>/dev/null; then
      if echo "$HOMEBREW_PACKAGES_INSTALLED" | grep -q "^rust$"; then
        echo "  Rust (via Homebrew)"
        # Remove rust from missing packages
        local new_missing=()
        for pkg in "${MISSING_BREW_PACKAGES[@]}"; do
          if [[ "$pkg" != "rust" ]]; then
            new_missing+=("$pkg")
          fi
        done
        MISSING_BREW_PACKAGES=("${new_missing[@]}")
      fi
    fi
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
    echo ""
    echo "  C++ headers not accessible - this often requires reinstalling Command Line Tools"
    echo ""
    echo "   Try these solutions in order:"
    echo "   1. Reset Xcode path: sudo xcode-select --reset"
    echo "   2. If that doesn't work, completely reinstall CLT:"
    echo "      sudo rm -rf /Library/Developer/CommandLineTools"
    echo "      xcode-select --install"
    echo ""
    echo "   Note: The reinstall can take 10-15 minutes to download and install."
  fi
}

platform_check_status() {
  local has_installable_missing=false

  if [[ ${#MISSING_BREW_PACKAGES[@]} -gt 0 ]]; then
    if [[ "$HAS_HOMEBREW" == true ]]; then
      echo "Missing Homebrew packages (will install):"
      for package in "${MISSING_BREW_PACKAGES[@]}"; do
        echo "   - $package"
      done
      has_installable_missing=true
    else
      echo "Homebrew not available, cannot install:"
      for package in "${MISSING_BREW_PACKAGES[@]}"; do
        echo "   - $package"
      done
      echo ""
      echo "Please install Homebrew from https://brew.sh and re-run this script."
      exit 1
    fi
  fi

  if [[ "$has_installable_missing" == false ]]; then
    echo "All dependencies are satisfied"
  fi
}

platform_install_dependencies() {
  if [[ ${#MISSING_BREW_PACKAGES[@]} -gt 0 ]] && [[ "$HAS_HOMEBREW" == true ]]; then
    echo "Installing missing Homebrew packages: ${MISSING_BREW_PACKAGES[*]}"
    if brew install "${MISSING_BREW_PACKAGES[@]}"; then
      echo "All missing packages have been installed"
      # Refresh the installed packages list
      HOMEBREW_PACKAGES_INSTALLED="$(brew list -1 2>/dev/null || true)"
    else
      echo "Failed to install some packages"
      exit 1
    fi
    echo ""
  fi
}

platform_setup_environment() {
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
      export CPATH="$CPATH:$SDKROOT/usr/include"
      echo "Set SDKROOT to $SDKROOT"
    fi
  fi
}

platform_post_compile_hooks() {
  # If you have already compiled Rambo explicitly via `mix compile.rambo`, and you
  # are still seeing the following error:
  #
  # ```
  # sh: /path_to_directory/Lightning/_build/dev/lib/rambo/priv/rambo: No such file or directory
  # sh: line 0: exec: /path_to_directory/Lightning/_build/dev/lib/rambo/priv/rambo: cannot execute: No such file or directory
  # ```
  #
  # You can try renaming `deps/rambo/priv/rambo-mac` to `deps/rambo/priv/rambo`.

  echo "Compiling platform-specific dependencies..."
  mix compile.rambo
}
