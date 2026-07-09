#!/usr/bin/env bash
# Router for the /bot slash command. Arg: "<room_name>" | "unbind"/"stop" | "status" | ""
#
# Default mode: /bot creates a per-session room and binds this session; the Stop
# hook posts this session's replies there. Writes .claude/.bot-binding.json.
#
# Global-room mode (BOT_GLOBAL_ROOM_NAME set): /bot still OPTS IN per session —
# nothing posts until you run it — but every opted-in session shares ONE room
# (host-derived id). /bot marks this session opted-in and ensures the shared
# room is bound once (reused across sessions). /bot stop removes THIS session's
# opt-in only, leaving the shared room for other sessions. /bot status reports
# whether this session is opted in.
set -euo pipefail
SID="${BOT_SESSION_ID:?run in a session started with the plugin}"
DIR="$(dirname "$0")"
BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"
ARG="${1:-status}"

# shellcheck source=/dev/null
. "$DIR/global-id.sh" 2>/dev/null || true

GID=""
command -v global_session_id >/dev/null 2>&1 && GID=$(global_session_id)

# ── Global-room mode ────────────────────────────────────────────────────────
if [ -n "$GID" ]; then
  REAL_SID="$SID"   # opt-in is keyed by the real per-session id
  case "$ARG" in
    status)
      if optin_has "$REAL_SID"; then
        echo "BOUND to shared room \"$BOT_GLOBAL_ROOM_NAME\" (this session posts)"
      else
        echo "NOT bound (run /bot to post this session to \"$BOT_GLOBAL_ROOM_NAME\")"
      fi
      ;;
    unbind|stop)
      optin_remove "$REAL_SID"
      echo "STOPPED — this session no longer posts to \"$BOT_GLOBAL_ROOM_NAME\""
      ;;
    *)
      # Ensure the shared room is bound once (idempotent: bind_first checks
      # status; the server's bind is unbind-old-then-bind, so a repeat is safe).
      R=$("$DIR/bot.sh" bot_status "$GID" 2>/dev/null)
      if [ "$(printf '%s' "$R" | jq -r '.bound // false' 2>/dev/null)" != "true" ]; then
        ARGS=$(jq -cn --arg n "$BOT_GLOBAL_ROOM_NAME" '{room_name:$n}')
        B=$("$DIR/bot.sh" bot_bind "$GID" "$ARGS")
        if [ "$(jq -r '.ok // false' <<<"$B")" != "true" ]; then
          echo "$B" | jq -r '"FAILED to bind: \(.reason // "unknown")"'
          exit 0
        fi
      fi
      optin_add "$REAL_SID"
      # Anchor the shared session id for the Stop hook (fallback lookup).
      mkdir -p "$(dirname "$BINDING")"
      jq -cn --arg sid "$GID" --arg n "$BOT_GLOBAL_ROOM_NAME" '{session_id:$sid,room_name:$n}' > "$BINDING"
      echo "BOUND to shared room \"$BOT_GLOBAL_ROOM_NAME\" — this session now posts"
      ;;
  esac
  exit 0
fi

# ── Default (per-session room) mode ─────────────────────────────────────────
case "$ARG" in
  status)
    R=$("$DIR/bot.sh" bot_status "$SID")
    echo "$R" | jq -r 'if .bound then "BOUND to room \"\(.room_name)\"" else "NOT bound" end'
    ;;
  unbind|stop)
    R=$("$DIR/bot.sh" bot_unbind "$SID")
    rm -f "$BINDING"
    echo "$R" | jq -r 'if .was_bound then "UNBOUND and left room" else "was not bound" end'
    ;;
  *)
    ARGS=$(jq -cn --arg n "$ARG" '{room_name:$n}')
    R=$("$DIR/bot.sh" bot_bind "$SID" "$ARGS")
    if [ "$(jq -r '.ok // false' <<<"$R")" = "true" ]; then
      mkdir -p "$(dirname "$BINDING")"
      jq -c --arg sid "$SID" '{session_id:$sid,room_name:.room_name}' <<<"$R" > "$BINDING"
      echo "$R" | jq -r '"BOUND to room \"\(.room_name)\"" + (if .rebound then " — auto-unbound previous room" else "" end)'
    else
      echo "$R" | jq -r '"FAILED to bind: \(.reason // "unknown")"'
    fi
    ;;
esac
