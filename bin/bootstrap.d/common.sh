#!/usr/bin/env bash
# Common functions and orchestration for bootstrap script
# Sourced by bin/bootstrap - do not execute directly

# Shared state variables
OS=""
ARCH=""
MISSING_SYSTEM_DEPS=()

# Get the directory where bootstrap.d lives
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Terminal styling helpers (step/ok/warn/err + colour vars). Sourced here so
# every consumer of common.sh - bootstrap, worktree, the platform files - gets
# them without its own source line.
source "$BOOTSTRAP_DIR/style.sh"

detect_and_source_platform() {
  OS="$(uname)"
  ARCH="$(uname -m)"

  case "$OS" in
  Darwin)
    source "$BOOTSTRAP_DIR/darwin.sh"
    ;;
  Linux)
    local distro=""
    if [[ -f /etc/os-release ]]; then
      # shellcheck source=/dev/null
      source /etc/os-release
      distro="${ID:-unknown}"
    fi

    case "$distro" in
    ubuntu | debian)
      source "$BOOTSTRAP_DIR/linux-debian.sh"
      ;;
    *)
      # Fallback: detect package manager
      if command -v apt-get &>/dev/null; then
        source "$BOOTSTRAP_DIR/linux-debian.sh"
      else
        {
          err "Unsupported Linux distribution: $distro"
          echo "Currently supported: Debian, Ubuntu (or any distro with apt-get)"
        } >&2
        exit 1
      fi
      ;;
    esac
    ;;
  *)
    {
      err "Unsupported operating system: $OS"
      echo "Currently supported: macOS (Darwin), Linux (Debian/Ubuntu)"
    } >&2
    exit 1
    ;;
  esac
}

check_common_dependencies() {
  if command -v node &>/dev/null; then
    echo "  Node.js: $(node --version)"
  else
    MISSING_SYSTEM_DEPS+=("Node.js")
  fi

  if command -v elixir &>/dev/null; then
    local elixir_version
    elixir_version="$(elixir --version 2>/dev/null | grep "^Elixir" | head -1 || echo "version unknown")"
    echo "  Elixir: $elixir_version"
  else
    MISSING_SYSTEM_DEPS+=("Elixir")
  fi
}

check_critical_dependencies() {
  local has_critical_missing=false

  if [[ ${#MISSING_SYSTEM_DEPS[@]} -gt 0 ]]; then
    {
      err "Missing critical system dependencies:"
      printf '   - %s\n' "${MISSING_SYSTEM_DEPS[@]}"
    } >&2
    has_critical_missing=true
  fi

  if [[ "$has_critical_missing" == true ]]; then
    {
      printf '%s\n' \
        "" \
        "Please install the missing dependencies and re-run this script."
    } >&2
    exit 1
  fi
}

detect_stale_native_caches() {
  # Check for stale CMake caches that can occur when:
  # - Using git worktrees with copied dependencies
  # - Moving/renaming the repository directory
  # - Restoring from backup at a different path
  # - Syncing code between machines with different paths

  local found_stale_cache=false
  local current_repo_path
  current_repo_path="$(pwd)"

  # Search for any CMakeCache.txt files in dependency build directories
  while IFS= read -r cache_file; do
    if [[ -f "$cache_file" ]]; then
      local cached_path
      cached_path=$(grep "CMAKE_HOME_DIRECTORY:INTERNAL=" "$cache_file" 2>/dev/null | cut -d= -f2)

      if [[ -n "$cached_path" ]]; then
        # Extract the expected current path from the cached path
        # Replace the old repo path prefix with current repo path
        local dep_suffix="${cached_path#*/deps/}"
        local expected_path="$current_repo_path/deps/$dep_suffix"

        if [[ "$cached_path" != "$expected_path" ]]; then
          if [[ "$found_stale_cache" == false ]]; then
            echo "Detected stale CMake cache(s)"
            found_stale_cache=true
          fi
          echo "   Package: $(echo "$cache_file" | cut -d/ -f2)"
          echo "   Expected: $expected_path"
          echo "   Found:    $cached_path"
        fi
      fi
    fi
  done < <(find deps -name "CMakeCache.txt" -type f 2>/dev/null)

  if [[ "$found_stale_cache" == true ]]; then
    echo "Cleaning native dependency build artifacts..."

    # Clean CMake build directories (various common names)
    rm -rf deps/*/c_build deps/*/build deps/*/cmake-build 2>/dev/null || true

    # Clean compiled native libraries
    rm -rf deps/*/priv/*.so 2>/dev/null || true

    # Clean rebar3 build directories that may have stale paths
    rm -rf deps/*/_build 2>/dev/null || true

    echo "Native dependency caches cleaned"
  fi
}

ensure_tool_versions() {
  if [[ ! -f .tool-versions ]]; then return; fi

  if command -v mise &>/dev/null; then
    step "Installing tool versions via mise"
    mise install
  elif command -v asdf &>/dev/null; then
    step "Installing tool versions via asdf"
    asdf install
  else
    {
      warn "No version manager found (mise/asdf)."
      echo "Ensure versions in .tool-versions are installed manually."
    } >&2
  fi
}

# Assumes platform_setup_environment has already been called by the caller.
setup_project_directory() {
  step "Installing Elixir dependencies"
  mix deps.get

  detect_stale_native_caches

  step "Compiling Elixir dependencies"
  mix deps.compile

  # Clean up stray object file created by crc32cer cmake compilation
  # This file sometimes escapes the build directory during cmake's compiler tests
  if [[ -f "-.o" ]]; then
    echo "Cleaning up stray cmake artifact (-.o)"
    rm -f ./-.o
  fi

  platform_post_compile_hooks

  step "Installing Node.js dependencies"
  npm install --prefix assets

  step "Setting up assets"
  mix assets.setup

  step "Installing Lightning components"
  mix lightning.install_runtime
  mix lightning.install_schemas
  mix lightning.install_adaptor_icons
}

setup_project_database() {
  step "Setting up database"
  mix "do" ecto.create, ecto.migrate
}

run_bootstrap() {
  step "Gathering environment information"
  echo "Platform: $OS $ARCH"
  echo ""

  ensure_tool_versions
  echo ""

  step "Checking common dependencies"
  check_common_dependencies
  echo ""

  step "Checking platform dependencies"
  platform_check_dependencies
  echo ""

  step "Environment Status Summary"
  check_critical_dependencies
  platform_check_status
  echo ""

  platform_install_dependencies

  step "Setting up environment"
  platform_setup_environment
  echo ""

  step "Setting up Elixir environment"
  mix local.hex --if-missing --force
  mix local.rebar --if-missing --force

  setup_project_directory

  step "Installing Playwright browsers"
  npx --prefix assets playwright install

  setup_project_database

  ok "All dependencies installed successfully!"
}
