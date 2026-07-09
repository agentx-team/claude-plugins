#!/usr/bin/env bash
# Launcher for the bot-channel stdio MCP server. The plugin ships without
# node_modules, so on first run this installs the (single) npm dependency
# into the plugin directory, then execs node. All output goes to stderr —
# stdout belongs to the MCP stdio protocol and must stay clean.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "bot-channel: node is required but not found in PATH" >&2
  exit 1
fi

if [ ! -d "$ROOT/node_modules/@modelcontextprotocol/sdk" ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "bot-channel: npm is required to install dependencies (first run) but not found in PATH" >&2
    exit 1
  fi
  echo "bot-channel: installing dependencies (first run)…" >&2
  npm install --prefix "$ROOT" --no-audit --no-fund --silent >&2
fi

exec node "$ROOT/scripts/channel.mjs"
