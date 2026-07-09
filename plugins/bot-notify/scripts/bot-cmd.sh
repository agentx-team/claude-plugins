#!/usr/bin/env bash
# Router for the /bot-notify:bot command. Arg: "" (bind) | "stop"/"unbind" | "status"
#
# bot-notify has exactly one room mode: ONE shared, outbound-only room per
# (bot, target user), bound with an EMPTY server session_id — so every host
# and every session using the same bot resolves to the SAME room (rebinding
# just reuses it, never duplicates it). /bot-notify:bot is a per-session
# opt-in: nothing posts from a session until it runs this command; running it
# again from another session shares the same room without affecting anyone
# else. /bot-notify:bot stop opts THIS session out only — the shared room and
# every other opted-in session are left untouched.
set -euo pipefail
DIR="$(dirname "$0")"
ROOM_NAME="${BOT_ROOM_NAME:-Claude Code}"

# shellcheck source=/dev/null
. "$DIR/optin.sh"

# Resolve the real Claude session id. Normally SessionStart exports it as
# BOT_SESSION_ID. Fall back to the active transcript filename (Claude Code
# stores transcripts at <config>/projects/<cwd-slug>/<session-id>.jsonl) for
# sessions where SessionStart hasn't fired yet (e.g. right after install).
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
  echo "NOT bound — could not determine the session id. Restart Claude Code (or run /clear) so the bot-notify plugin initializes, then try again."
  exit 0
}

# No argument ⇒ BIND (the common case). A leading "/bot" (from users typing
# "/bot-notify:bot /bot") is tolerated as "no argument".
ARG="${1:-}"
[ "$ARG" = "/bot" ] && ARG=""

case "$ARG" in
  status)
    if optin_has "$SID"; then
      echo "BOUND to shared room \"$ROOM_NAME\" (this session posts)"
    else
      echo "NOT bound (run /bot-notify:bot to post this session to \"$ROOM_NAME\")"
    fi
    ;;
  unbind|stop)
    optin_remove "$SID"
    echo "STOPPED — this session no longer posts to \"$ROOM_NAME\""
    ;;
  *)
    # Idempotent server-side: the room is identified by (bot, target user),
    # so a repeat bind REUSES the existing room (renaming it only if
    # BOT_ROOM_NAME changed) and never creates a duplicate.
    ARGS=$(jq -cn --arg n "$ROOM_NAME" '{room_name:$n, accept_delivery:false}')
    B=$("$DIR/bot.sh" bot_bind "" "$ARGS")
    if [ "$(jq -r '.ok // false' <<<"$B")" != "true" ]; then
      echo "$B" | jq -r '"FAILED to bind: \(.reason // "unknown")\(if (.detail // "") != "" then " — \(.detail)" else "" end)"'
      exit 0
    fi
    optin_add "$SID"
    echo "BOUND to shared room \"$ROOM_NAME\" — this session now posts"
    ;;
esac
