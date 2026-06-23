#!/bin/bash
# Call a frevana MCP tool via the local daemon.
#
# Thin wrapper around `frevana call` (provided by the prebuilt binary). This
# script exists for backward compatibility with the SKILL.md examples; the
# actual HTTP/JSON-RPC/SSE work is done inside the native binary so no
# Node.js / npm / jq is required on the host.
#
# Usage: bash scripts/frevana-call.sh <tool_name> '<json_args>'
#        bash scripts/frevana-call.sh --help
#
# Example:
#   bash scripts/frevana-call.sh frevana_scrape '{"url":"https://example.com","provider":"url"}'
#   bash scripts/frevana-call.sh frevana_ask '{"provider":"chatgpt","prompt":"hello"}'
#   bash scripts/frevana-call.sh frevana_status
#
# Output: Tool result text to stdout, errors to stderr
# Exit codes: 0 = success, 1 = error
#
# Environment variables:
#   FREVANA_PORT     — daemon port (default: 12306)
#   FREVANA_TIMEOUT  — request timeout in seconds (default: 180)

set -euo pipefail

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'HELP'
frevana-call — call a frevana MCP tool via the local daemon.

Usage:
  bash scripts/frevana-call.sh <tool_name> '<json_args>'

Tools:
  frevana_scrape   Scrape a web page as Markdown
  frevana_ask      Ask an AI platform a question
  frevana_x_search_topic  Search X (Twitter) posts by topic
  frevana_meta_ads_search  Search Meta Ads Library
  frevana_publish  Publish to Twitter/Facebook/LinkedIn
  frevana_status   Check Chrome connection status

Examples:
  bash scripts/frevana-call.sh frevana_scrape '{"url":"https://example.com","provider":"url"}'
  bash scripts/frevana-call.sh frevana_ask '{"provider":"chatgpt","prompt":"what is AI?"}'
  bash scripts/frevana-call.sh frevana_x_search_topic '{"topic":"vibe coding","sort":"top","count":10,"fetchMode":"full","timeout":60000}'
  bash scripts/frevana-call.sh frevana_meta_ads_search '{"keyword":"frevana","country":"CN","active_status":"active","maxResults":10}'
  bash scripts/frevana-call.sh frevana_publish '{"provider":"twitter","text":"Hello!"}'
  bash scripts/frevana-call.sh frevana_status '{}'

Environment:
  FREVANA_PORT     Daemon port (default: 12306)
  FREVANA_TIMEOUT  Request timeout in seconds (default: 180)
HELP
  exit 0
fi

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

TOOL_NAME="${1:?Error: missing tool name. Run with --help for usage.}"
TOOL_ARGS="${2:-}"
[ -z "$TOOL_ARGS" ] && TOOL_ARGS='{}'
DAEMON_PORT="${FREVANA_PORT:-12306}"
TIMEOUT_SEC="${FREVANA_TIMEOUT:-180}"
TIMEOUT_MS=$(( TIMEOUT_SEC * 1000 ))

# ---------------------------------------------------------------------------
# Resolve binary path. setup.sh installs to ~/.frevana/bin/frevana[.exe]; if
# the user has run their own install elsewhere, fall back to PATH lookup.
# ---------------------------------------------------------------------------

EXT=""
case "$(uname -s 2>/dev/null || echo)" in
  MINGW*|MSYS*|CYGWIN*) EXT=".exe" ;;
esac

FREVANA_BIN="$HOME/.frevana/bin/frevana${EXT}"
if [ ! -x "$FREVANA_BIN" ]; then
  if command -v frevana >/dev/null 2>&1; then
    FREVANA_BIN="$(command -v frevana)"
  else
    echo "Error: frevana binary not found at $FREVANA_BIN and not on PATH." >&2
    echo "Run 'bash scripts/setup.sh' first to install it." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Preflight: daemon must be running
# ---------------------------------------------------------------------------

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is not installed." >&2
  exit 1
fi

if ! curl -s --max-time 2 "http://127.0.0.1:${DAEMON_PORT}/health" >/dev/null 2>&1; then
  echo "Error: Frevana daemon is not running on port ${DAEMON_PORT}." >&2
  echo "Run 'bash scripts/setup.sh' first to start the daemon." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Delegate to the binary's `call` subcommand. The binary owns JSON building,
# HTTP transport, SSE parsing, and content extraction.
# ---------------------------------------------------------------------------

exec "$FREVANA_BIN" call "$TOOL_NAME" "$TOOL_ARGS" --port "$DAEMON_PORT" --timeout "$TIMEOUT_MS"
