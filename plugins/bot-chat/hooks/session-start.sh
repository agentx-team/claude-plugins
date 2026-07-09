#!/usr/bin/env bash
# SessionStart: export the session id so /bot and the Stop hook target the
# same binding.
#
# Global-room mode (BOT_GLOBAL_ROOM_NAME set): every Claude Code session on this
# machine funnels into ONE shared Matrix room. We derive a deterministic global
# session id (room name + host LAN IP, hashed), export it as BOT_SESSION_ID, and
# auto-bind it once (idempotent: bind first checks status, and the server's bind
# is "unbind-old-then-bind" so a repeat is harmless). No /bot needed.
#
# Default mode (unset): behavior unchanged — export the real Claude session id;
# the user runs /bot to bind a per-session room.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id' <<<"$IN")
DIR="$(dirname "$0")/../scripts"
BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"

# shellcheck source=/dev/null
. "$DIR/global-id.sh" 2>/dev/null || true

GID=""
command -v global_session_id >/dev/null 2>&1 && GID=$(global_session_id)

if [ -n "$GID" ]; then
  SID="$GID"
  # Auto-bind the shared room in the background (best-effort; never block/fail
  # session start). Only (re)bind when not already bound to avoid re-creating
  # the room on every session.
  (
    R=$("$DIR/bot.sh" bot_status "$GID" 2>/dev/null)
    if [ "$(printf '%s' "$R" | jq -r '.bound // false' 2>/dev/null)" != "true" ]; then
      ARGS=$(jq -cn --arg n "$BOT_GLOBAL_ROOM_NAME" '{room_name:$n}')
      B=$("$DIR/bot.sh" bot_bind "$GID" "$ARGS" 2>/dev/null)
      if [ "$(printf '%s' "$B" | jq -r '.ok // false' 2>/dev/null)" = "true" ]; then
        mkdir -p "$(dirname "$BINDING")"
        jq -cn --arg sid "$GID" --arg n "$BOT_GLOBAL_ROOM_NAME" '{session_id:$sid,room_name:$n}' > "$BINDING"
      fi
    else
      # Already bound elsewhere on this host — just anchor the binding file so
      # this session's Stop hook targets the shared room.
      mkdir -p "$(dirname "$BINDING")"
      jq -cn --arg sid "$GID" --arg n "$BOT_GLOBAL_ROOM_NAME" '{session_id:$sid,room_name:$n}' > "$BINDING"
    fi
  ) >/dev/null 2>&1 &
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export BOT_SESSION_ID=$SID" >> "$CLAUDE_ENV_FILE"
fi
exit 0
