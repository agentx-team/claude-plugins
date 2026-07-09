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
DIR="$(dirname "$0")"

# Resolve the real Claude session id. Normally the SessionStart hook exports it
# as BOT_SESSION_ID (via CLAUDE_ENV_FILE). But that hook may not have run for
# THIS session — e.g. a session that was compacted/cleared (SessionStart there
# fires with source "compact"/"clear", which older plugin versions didn't match)
# or one already open when the plugin was installed. Rather than hard-crash with
# an unbound-variable error, fall back to the active transcript filename: Claude
# Code stores transcripts at <config>/projects/<cwd-slug>/<session-id>.jsonl, and
# that basename IS the session id the Stop hook reads from stdin — so per-session
# opt-in markers still line up.
resolve_session_id() {
  if [ -n "${BOT_SESSION_ID:-}" ]; then printf '%s' "$BOT_SESSION_ID"; return 0; fi
  local base cwd slug pdir f
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
  slug=$(printf '%s' "$cwd" | sed 's#[^a-zA-Z0-9]#-#g')
  pdir="$base/$slug"
  if [ -d "$pdir" ]; then
    f=$(ls -t "$pdir"/*.jsonl 2>/dev/null | head -1)
    [ -n "$f" ] && { basename "$f" .jsonl; return 0; }
  fi
  return 1
}
SID=$(resolve_session_id) || {
  echo "NOT bound — could not determine the session id. Restart Claude Code (or run /clear) so the bot-chat plugin initializes, then try /bot again."
  exit 0
}
BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"
# No argument ⇒ BIND (the common case): `/bot` alone opts this session in.
# `status` / `stop` / `unbind` are explicit keywords; anything else is a room
# name (default mode only). A leading "/bot" (from users typing `/bot-chat:bot
# /bot`) is tolerated as "no argument".
ARG="${1:-}"
[ "$ARG" = "/bot" ] && ARG=""

# shellcheck source=/dev/null
. "$DIR/global-id.sh" 2>/dev/null || true

GID=""
command -v global_session_id >/dev/null 2>&1 && GID=$(global_session_id)

# ── Global-room / share-room mode ───────────────────────────────────────────
# The shared room is bound OUTBOUND-ONLY (accept_delivery=false) with an EMPTY
# server session id: on the server that is the single shared (bot, "") binding,
# reused by every host session. Inbound messages in the shared room therefore
# flow to the AgentX agent, not back into any one Claude Code session — so we
# never poll bot_receive here. /bot is still a per-session opt-in (keyed by the
# real session id) that only gates whether THIS session's turns are posted out.
if [ -n "$GID" ]; then
  REAL_SID="$SID"   # opt-in is keyed by the real per-session id
  case "$ARG" in
    status)
      if optin_has "$REAL_SID"; then
        echo "BOUND to shared room \"$BOT_GLOBAL_ROOM_NAME\" (this session posts)"
      else
        echo "NOT bound (run the /bot command to post this session to \"$BOT_GLOBAL_ROOM_NAME\")"
      fi
      ;;
    unbind|stop)
      optin_remove "$REAL_SID"
      echo "STOPPED — this session no longer posts to \"$BOT_GLOBAL_ROOM_NAME\""
      ;;
    *)
      # Bind the shared outbound-only room. This is idempotent server-side: the
      # room is identified by (bot, target user), so a repeat bind REUSES the
      # existing room (renaming it only if BOT_GLOBAL_ROOM_NAME changed) and never
      # creates a duplicate. session_id stays empty (share rooms hold no session).
      ARGS=$(jq -cn --arg n "$BOT_GLOBAL_ROOM_NAME" '{room_name:$n, accept_delivery:false}')
      B=$("$DIR/bot.sh" bot_bind "" "$ARGS")
      if [ "$(jq -r '.ok // false' <<<"$B")" != "true" ]; then
        echo "$B" | jq -r '"FAILED to bind: \(.reason // "unknown")"'
        exit 0
      fi
      optin_add "$REAL_SID"
      # Anchor the shared room for the Stop hook (empty session = outbound-only).
      mkdir -p "$(dirname "$BINDING")"
      jq -cn --arg n "$BOT_GLOBAL_ROOM_NAME" '{session_id:"",room_name:$n}' > "$BINDING"
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
    # No room name given ⇒ name the room after the working-directory leaf.
    # Per-session mode wants room replies delivered back into THIS session, so it
    # opts into delivery explicitly (accept_delivery now defaults to false).
    ROOM="$ARG"
    [ -z "$ROOM" ] && ROOM=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")
    ARGS=$(jq -cn --arg n "$ROOM" '{room_name:$n, accept_delivery:true}')
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
