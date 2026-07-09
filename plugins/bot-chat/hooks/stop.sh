#!/usr/bin/env bash
# Stop: when a turn finishes, push the last assistant message to the bound room.
#
# Global-room mode (BOT_GLOBAL_ROOM_NAME set): push to the shared global session
# id — EVERY session on this host posts into the one room, so there is no
# per-session match to gate on.
#
# Default mode: gated on .claude/.bot-binding.json (written by /bot) and on the
# session id matching, so other sessions in the same project don't cross-post.
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
  # Global mode: all sessions share one room, so prefix each message with the
  # session's identity so the reader can tell them apart. Use the leaf of the
  # session cwd (e.g. /home/core/Documents/tmp/bot → "bot"), falling back to the
  # hook's own cwd if the input omits it.
  CWD=$(jq -r '.cwd // ""' <<<"$IN")
  [ -z "$CWD" ] && CWD="$PWD"
  LEAF=$(basename "$CWD")
  MSG="${LEAF}:
${MSG}"
  ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
  # Always push to the shared room. bot_send returns a non-error ok:false when
  # not yet bound (SessionStart binds asynchronously), so an early turn simply
  # no-ops rather than erroring.
  "$DIR/bot.sh" bot_send "$GID" "$ARGS" >/dev/null 2>&1 &
  exit 0
fi

ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')

# Default mode: only the session that ran /bot posts, to its own room.
BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"
[ -f "$BINDING" ] || exit 0
[ "$(jq -r '.session_id // ""' "$BINDING")" = "$SID" ] || exit 0
"$DIR/bot.sh" bot_send "$SID" "$ARGS" >/dev/null 2>&1 &
exit 0
