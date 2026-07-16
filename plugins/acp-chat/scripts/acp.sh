#!/usr/bin/env bash
# acp-chat unified CLI. One entry point for the daemon lifecycle + room control.
#
#   ./scripts/acp.sh [command] [options]
#
# With no command (or help/-h/--help) it prints usage. All state lives under
# ACP_STATE_DIR (default <plugin>/state); the daemon recovers it on every start.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$ROOT}"
STATE_DIR="${ACP_STATE_DIR:-$ROOT/state}"
PIDFILE="$STATE_DIR/acp-chatd.pid"
LOG="$STATE_DIR/daemon.log"
ROOMS="$STATE_DIR/rooms.json"
ENTRY="$ROOT/bin/acp-chatd.mjs"

usage() {
  cat <<'EOF'
acp-chat — Kiro v3 ACP multi-room chat daemon

Usage: ./scripts/acp.sh <command> [options]

Daemon lifecycle:
  start [--fg]     Start the daemon (background; --fg runs in foreground).
                   Recovers all persisted rooms (bot bindings + ACP sessions).
  stop             Stop the daemon. State is PRESERVED — a later `start`
                   recovers every room. Does NOT leave any IM room.
  restart          Stop then start (reloads code + recovers state).
  status           Show daemon pid + the persisted rooms it manages.

Room control:
  rooms            List persisted rooms (alias of the room table in `status`).
  stop-all [--keep-control]
                   CLOSE AND EXIT ALL ROOMS: stop the daemon, then unbind every
                   room on the bot server (leaves the IM rooms) and clear the
                   local store. --keep-control keeps the control room; default
                   removes it too (a fresh one is created on next `start`).

Other:
  help, -h, --help  Show this message (also shown when no command is given).

Env: BOT_ID, BOT_API_KEY required. See README for the full variable list.
EOF
}

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

require_bot_env() {
  if [ -z "${BOT_ID:-}" ] || [ -z "${BOT_API_KEY:-}" ]; then
    echo "acp-chat: BOT_ID and BOT_API_KEY must be exported (see README)" >&2
    exit 1
  fi
}

KIROPIDFILE="$STATE_DIR/kiro.pid"

# Reap the kiro ACP process group recorded in kiro.pid. The daemon normally
# kills its own kiro child on graceful shutdown; this is a BACKSTOP for the case
# where the daemon died without cleanup (e.g. kill -9), which would otherwise
# leave an orphaned `kiro-cli acp` (+ its acp-server.js child) behind.
reap_kiro() {
  [ -f "$KIROPIDFILE" ] || return 0
  local kpid; kpid="$(cat "$KIROPIDFILE" 2>/dev/null || true)"
  if [ -n "$kpid" ] && kill -0 "$kpid" 2>/dev/null; then
    echo "acp-chat: reaping kiro process group (pid $kpid)…"
    kill -TERM -"$kpid" 2>/dev/null || kill -TERM "$kpid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do kill -0 "$kpid" 2>/dev/null || break; sleep 0.4; done
    kill -KILL -"$kpid" 2>/dev/null || kill -KILL "$kpid" 2>/dev/null || true
  fi
  rm -f "$KIROPIDFILE"
}

stop_daemon() {
  if running; then
    local pid; pid="$(cat "$PIDFILE")"
    echo "acp-chat: stopping daemon (pid $pid)…"
    kill "$pid" 2>/dev/null || true
    # Give the daemon its graceful window: it awaits kiro's exit before quitting.
    for _ in $(seq 1 12); do kill -0 "$pid" 2>/dev/null || break; sleep 0.4; done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
  reap_kiro   # backstop: clean up kiro even if the daemon couldn't
}

do_start() {
  require_bot_env
  command -v node >/dev/null 2>&1 || { echo "acp-chat: node not found in PATH" >&2; exit 1; }
  command -v kiro-cli >/dev/null 2>&1 || {
    echo "acp-chat: kiro-cli not found in PATH" >&2; exit 1; }
  mkdir -p "$STATE_DIR"
  if running; then
    echo "acp-chat: already running (pid $(cat "$PIDFILE")). Use restart to recycle."
    exit 0
  fi
  if [ "${1:-}" = "--fg" ]; then
    exec node "$ENTRY"
  fi
  nohup node "$ENTRY" >>"$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  sleep 1
  if running; then
    echo "acp-chat: started (pid $(cat "$PIDFILE")). Recovered state from $ROOMS."
    echo "acp-chat: tail -f \"$LOG\" for activity."
  else
    echo "acp-chat: failed to start — see $LOG" >&2
    exit 1
  fi
}

do_status() {
  if running; then echo "daemon: RUNNING (pid $(cat "$PIDFILE"))"; else echo "daemon: stopped"; fi
  if [ -f "$ROOMS" ] && command -v jq >/dev/null 2>&1; then
    echo "persisted rooms ($(jq '.rooms | length' "$ROOMS")):"
    jq -r '.rooms[] | "  - \(.roomName)\(if .control then " [control]" else "" end)  cwd=\(.cwd)  acp=\(.acpSessionId // "none")  handle=\(.botSid)"' "$ROOMS"
  else
    echo "persisted rooms: none yet ($ROOMS)"
  fi
}

# Close and exit ALL rooms: stop daemon, unbind every room on the server, clear
# the store. The daemon MUST be stopped first so it can't re-poll/rewrite state
# mid-purge. ACP sessions are left on kiro's disk (harmless — the cleared store
# means they are never reloaded).
do_stop_all() {
  require_bot_env
  local keep_control="no"
  [ "${1:-}" = "--keep-control" ] && keep_control="yes"
  stop_daemon
  if [ ! -f "$ROOMS" ]; then echo "acp-chat: no rooms to close."; return; fi
  ACP_KEEP_CONTROL="$keep_control" ACP_ROOT="$ROOT" node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
const { cfg } = await import(join(process.env.ACP_ROOT, 'src/config.mjs'))
const { bot } = await import(join(process.env.ACP_ROOT, 'src/bot-client.mjs'))
const FILE = join(cfg.stateDir, 'rooms.json')
let state
try { state = JSON.parse(readFileSync(FILE, 'utf8')) } catch { state = { schema: 1, rooms: [] } }
const keepControl = process.env.ACP_KEEP_CONTROL === 'yes'
const kept = []
let closed = 0
for (const r of state.rooms) {
  if (keepControl && r.control) { kept.push(r); continue }
  const res = await bot.unbind(r.botSid)
  console.log(`  closed "${r.roomName}" (${r.botSid}) → was_bound=${res?.was_bound ?? '?'}`)
  closed++
}
writeFileSync(FILE, JSON.stringify({ schema: 1, rooms: kept }, null, 2))
console.log(`acp-chat: closed ${closed} room(s); ${kept.length} kept.`)
NODE
  echo "acp-chat: all rooms closed. Run './scripts/acp.sh start' for a fresh control room."
}

CMD="${1:-help}"; shift || true
case "$CMD" in
  start)              do_start "${1:-}" ;;
  stop)               stop_daemon; echo "acp-chat: stopped. State preserved — run start to recover." ;;
  restart)            stop_daemon; do_start "${1:-}" ;;
  status|rooms)       do_status ;;
  stop-all|close-all) do_stop_all "${1:-}" ;;
  help|-h|--help|"")  usage ;;
  *)                  echo "acp-chat: unknown command '$CMD'"; echo; usage; exit 2 ;;
esac
