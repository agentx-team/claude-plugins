#!/usr/bin/env bash
# Stop: when a turn finishes, push the last assistant message to the bound room
# — but ONLY for sessions the user explicitly opted in via /bot.
#
# Global-room mode (BOT_GLOBAL_ROOM_NAME set): post to the shared room only if
# THIS session opted in (per-session marker keyed by the real session id). Many
# sessions share the room, so each message is prefixed with the session's cwd
# leaf so the reader can tell them apart.
#
# Default mode: gated on .claude/.bot-binding.json (written by /bot) and on the
# session id matching, so only the session that ran /bot posts, to its own room.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id' <<<"$IN")
DIR="$(dirname "$0")/../scripts"

# shellcheck source=/dev/null
. "$DIR/global-id.sh" 2>/dev/null || true
GID=""
command -v global_session_id >/dev/null 2>&1 && GID=$(global_session_id)

MSG=$(jq -r '.last_assistant_message // ""' <<<"$IN")
[ -z "$MSG" ] && exit 0

if [ -n "$GID" ]; then
  # Global mode: post only if this session opted in via /bot.
  command -v optin_has >/dev/null 2>&1 && optin_has "$SID" || exit 0
  # Label with the session cwd leaf (Claude Code exposes no session name to
  # hooks), e.g. /home/core/Documents/tmp/bot → "bot".
  CWD=$(jq -r '.cwd // ""' <<<"$IN")
  [ -z "$CWD" ] && CWD="$PWD"
  LEAF=$(basename "$CWD")
  MSG="${LEAF}:
${MSG}"
  ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
  "$DIR/bot.sh" bot_send "$GID" "$ARGS" >/dev/null 2>&1 &
  exit 0
fi

# Default mode: only the session that ran /bot posts, to its own room.
BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"
[ -f "$BINDING" ] || exit 0
[ "$(jq -r '.session_id // ""' "$BINDING")" = "$SID" ] || exit 0
ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
"$DIR/bot.sh" bot_send "$SID" "$ARGS" >/dev/null 2>&1 &
exit 0
