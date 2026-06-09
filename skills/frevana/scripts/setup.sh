#!/bin/bash
# Frevana CLI bootstrap — download the prebuilt binary from GitHub Releases on
# first run, then delegate everything (daemon management, health checks, Chrome
# check, update banners) to the binary itself via `frevana setup-host`.
#
# This keeps the bash script tiny: anything inside the binary is upgraded by
# `frevana update`, so the bootstrap rarely needs to change.
#
# Usage: bash scripts/setup.sh [--help] [--snooze]
#
# Exit codes (forwarded from `frevana setup-host`):
#   0 — ready, Chrome connected
#   1 — error (bootstrap or daemon)
#   2 — ready, Chrome disconnected
#
# Environment:
#   FREVANA_PORT     — daemon port (default: 12306)
#   FREVANA_VERSION  — pin a specific release version (default: latest)

set -euo pipefail

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'HELP'
Frevana bootstrap — download the prebuilt binary, then run `frevana setup-host`.

Usage:
  bash scripts/setup.sh           Install binary if missing, start daemon, report status
  bash scripts/setup.sh --snooze  Snooze update notifications (forwarded to binary)
  bash scripts/setup.sh --help    Show this help

Exit codes (from `frevana setup-host`):
  0  Ready, Chrome connected
  1  Error
  2  Ready, Chrome disconnected

Environment:
  FREVANA_PORT     Daemon port (default: 12306)
  FREVANA_VERSION  Pin a specific release version (default: latest)
HELP
  exit 0
fi

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

FREVANA_STATE="$HOME/.frevana"
FREVANA_BIN_DIR="$FREVANA_STATE/bin"
DAEMON_PORT="${FREVANA_PORT:-12306}"
LOCKFILE="/tmp/frevana-setup.lock"
RELEASES_REPO="FinpeakInc/frevana-cli-releases"
# Download URLs use GitHub's /releases/{latest|tag/<ver>}/download/<file>
# redirect (302 → asset CDN). This deliberately avoids api.github.com because
# that endpoint is rate-limited to 60 requests/hour per IP (unauthenticated)
# and corporate / shared-NAT users hit 403 on first install. The redirect
# endpoint shares github.com's much more generous limits.
RELEASES_BASE="https://github.com/${RELEASES_REPO}/releases"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

fail() {
  local msg="$1"
  local escaped
  escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
  echo "{\"status\":\"error\",\"message\":\"${escaped}\"}"
  exit 1
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || fail "'$1' is not installed. Please install $1 first."
}

# Detect platform → release asset suffix. Fail loud on unsupported combo.
detect_platform() {
  local uname_s uname_m platform arch
  uname_s=$(uname -s 2>/dev/null || echo "")
  uname_m=$(uname -m 2>/dev/null || echo "")

  case "$uname_s" in
    Darwin) platform="darwin" ;;
    Linux)  platform="linux" ;;
    MINGW*|MSYS*|CYGWIN*) platform="win32" ;;
    *) fail "Unsupported OS: ${uname_s}. Frevana binaries are published for darwin, linux, and win32 only." ;;
  esac

  case "$uname_m" in
    arm64|aarch64) arch="arm64" ;;
    x86_64|amd64)  arch="x64" ;;
    *) fail "Unsupported CPU architecture: ${uname_m}. Frevana binaries are published for arm64 and x64 only." ;;
  esac

  case "${platform}-${arch}" in
    darwin-arm64|linux-x64|win32-x64) : ;;
    *) fail "No Frevana binary is published for ${platform}-${arch}. Supported: darwin-arm64, linux-x64, win32-x64." ;;
  esac

  echo "${platform}-${arch}"
}

# sha256 hex of a file. Falls back across sha256sum / shasum.
sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    fail "Neither sha256sum nor shasum is available. Install one to verify downloads."
  fi
}

# Build the download URL for a single release asset. Uses /releases/latest/
# download/<file> for the floating "latest" pointer, or /releases/download/
# v<ver>/<file> when FREVANA_VERSION pins a specific version. Both forms 302
# to the asset CDN; neither hits api.github.com.
release_download_url() {
  local file="$1"
  if [ -n "${FREVANA_VERSION:-}" ]; then
    printf '%s' "${RELEASES_BASE}/download/v${FREVANA_VERSION}/${file}"
  else
    printf '%s' "${RELEASES_BASE}/latest/download/${file}"
  fi
}

# Install binary into $FREVANA_BIN with SHA256 verification. Resolves the
# asset entirely off the SHA256SUMS.txt file — no GitHub API call.
install_binary() {
  local platform_key="$1" target_path="$2"
  local version asset_name asset_url sums_url tmp_dir tmp_bin tmp_sums ext expected_hash actual_hash

  ext=""
  case "$platform_key" in *win32*) ext=".exe" ;; esac

  # Stage tmp dir on the SAME filesystem as the target so the final mv is atomic
  # and doesn't fail with cross-device link errors (common when /tmp is tmpfs).
  mkdir -p "$FREVANA_BIN_DIR"
  tmp_dir=$(mktemp -d "${FREVANA_BIN_DIR}/.install.XXXXXX") || fail "Failed to create temp directory under ${FREVANA_BIN_DIR}."
  # Explicit cleanup at the end of this function; an EXIT trap can't carry the
  # function-local $tmp_dir reliably across nested traps (RETURN trap behavior
  # varies across bash 3.2/4/5 + set -e). Doing it inline is portable.
  cleanup_install_tmp() { rm -rf "$tmp_dir" 2>/dev/null || true; }
  tmp_sums="${tmp_dir}/SHA256SUMS.txt"

  # Step 1: fetch SHA256SUMS.txt via the /releases/{latest|tag}/download/
  # redirect. This deliberately bypasses api.github.com so we don't hit the
  # 60/hour unauthenticated rate limit. The redirect ultimately resolves to
  # the GitHub release-assets CDN.
  sums_url=$(release_download_url "SHA256SUMS.txt")
  if [ -n "${FREVANA_VERSION:-}" ]; then
    echo "Using pinned version: v${FREVANA_VERSION}" >&2
  else
    echo "Fetching latest release manifest (no GitHub API)..." >&2
  fi
  if ! curl -sSL --max-time 30 --fail-with-body -o "$tmp_sums" "$sums_url" 2>/dev/null; then
    cleanup_install_tmp
    fail "Failed to download SHA256SUMS.txt from ${sums_url}"
  fi

  # Step 2: pick the line for our platform from SHA256SUMS.txt. Format is
  #   <hex>  *?frevana-<version>-<platform>-<arch>[.exe]
  # The version is encoded in the filename so we don't need a separate API
  # call to learn it.
  asset_name=$(awk -v suffix="-${platform_key}${ext}" '
    {
      name=$NF
      sub(/^\*/, "", name)
      if (index(name, suffix) > 0 && (substr(name, length(name) - length(suffix) + 1) == suffix)) {
        print name
        exit
      }
    }' "$tmp_sums")
  if [ -z "$asset_name" ]; then
    cleanup_install_tmp
    fail "SHA256SUMS.txt has no asset matching '${platform_key}${ext}'. URL: ${sums_url}"
  fi
  # Match `frevana-<numeric.dotted>-<platform>...`. Restrict the capture to
  # digits + dot so `-darwin-arm64` doesn't get absorbed (greedy `-` would
  # have made us return "1.1.1-darwin"). Pre-release tags like "-beta" would
  # need a richer regex; we ship stable semver so this stays simple.
  version=$(printf '%s' "$asset_name" | sed -nE 's/^frevana-([0-9][0-9.]*)-.*$/\1/p')
  echo "  Version: v${version}" >&2

  expected_hash=$(grep -F "$asset_name" "$tmp_sums" | head -1 | awk '{print $1}')
  if [ -z "$expected_hash" ]; then
    cleanup_install_tmp
    fail "No SHA256 entry for ${asset_name} in SHA256SUMS.txt."
  fi

  # Step 3: download the binary via the same redirect endpoint.
  asset_url=$(release_download_url "$asset_name")
  tmp_bin="${tmp_dir}/${asset_name}"
  echo "  Downloading ${asset_name}..." >&2
  if ! curl -sSL --max-time 300 --fail-with-body -o "$tmp_bin" "$asset_url" 2>/dev/null; then
    cleanup_install_tmp
    fail "Download failed: ${asset_url}"
  fi

  actual_hash=$(sha256_of "$tmp_bin")
  if [ "$expected_hash" != "$actual_hash" ]; then
    cleanup_install_tmp
    fail "Checksum mismatch for ${asset_name}: expected ${expected_hash}, got ${actual_hash}. Refusing to install."
  fi

  chmod +x "$tmp_bin"
  mv "$tmp_bin" "$target_path"
  cleanup_install_tmp
  echo "  Installed ${asset_name} -> ${target_path}" >&2
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

check_command curl

PLATFORM_KEY=$(detect_platform)
case "$PLATFORM_KEY" in *win32*) BIN_EXT=".exe" ;; *) BIN_EXT="" ;; esac
FREVANA_BIN="${FREVANA_BIN_DIR}/frevana${BIN_EXT}"

# ---------------------------------------------------------------------------
# --snooze: forward to binary (it owns the snooze state)
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--snooze" ]; then
  if [ ! -x "$FREVANA_BIN" ]; then
    fail "Cannot --snooze before initial install. Run 'bash scripts/setup.sh' first."
  fi
  exec "$FREVANA_BIN" snooze
fi

# ---------------------------------------------------------------------------
# Install binary if missing
# ---------------------------------------------------------------------------

if [ ! -x "$FREVANA_BIN" ]; then
  if ! mkdir "$LOCKFILE" 2>/dev/null; then
    LOCK_MTIME=$(stat -f %m "$LOCKFILE" 2>/dev/null || stat -c %Y "$LOCKFILE" 2>/dev/null || echo 0)
    LOCK_AGE=$(( $(date +%s) - LOCK_MTIME ))
    if [ "$LOCK_AGE" -lt 300 ]; then
      fail "Another installation is in progress. Wait a few minutes and try again."
    fi
    rm -rf "$LOCKFILE"
    mkdir "$LOCKFILE" 2>/dev/null || true
  fi
  # Best-effort cleanup if the script dies before reaching the explicit rm
  # below (e.g., install_binary fails mid-way).
  trap 'rm -rf "$LOCKFILE"' EXIT

  echo "Installing frevana binary for ${PLATFORM_KEY} (first-time setup)..." >&2
  install_binary "$PLATFORM_KEY" "$FREVANA_BIN"

  [ -x "$FREVANA_BIN" ] || fail "Installation completed but ${FREVANA_BIN} is not executable. Aborting."

  # Release the lock EXPLICITLY. The EXIT trap above is insufficient because
  # the final `exec` (a few lines down) replaces this shell process, and bash
  # does not fire EXIT traps on exec. Without this line the lock dir leaks at
  # /tmp/frevana-setup.lock and the next setup.sh run within 5 minutes will
  # incorrectly report "Another installation is in progress".
  rm -rf "$LOCKFILE"
fi

# ---------------------------------------------------------------------------
# Delegate everything else to the binary
# ---------------------------------------------------------------------------

exec "$FREVANA_BIN" setup-host --port "$DAEMON_PORT"
