#!/usr/bin/env bash
# Notification: forward "Claude needs your input" moments to the bound room so a
# human watching the IM chat can jump in — permission prompts, idle-waiting,
# MCP elicitation forms, and background-agent input requests. This is the
# mid-turn, human-in-the-loop counterpart to the Stop hook (turn-end results).
#
# Gating mirrors stop.sh exactly, so notifications only reach rooms this session
# actually posts to:
#   - Global/share-room mode: post to the shared room only if THIS session
#     opted in via /bot; prefix with the cwd leaf; empty server session.
#   - Default mode: gated on .claude/.bot-binding.json + session-id match; post
#     to this session's own room under its real session id.
#
# Notification hooks cannot block and have no decision control — pure side
# effect. Failures are swallowed; we never disturb the session.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id // ""' <<<"$IN")
DIR="$(dirname "$0")/../scripts"

# shellcheck source=/dev/null
. "$DIR/global-id.sh" 2>/dev/null || true
GID=""
command -v global_session_id >/dev/null 2>&1 && GID=$(global_session_id)

# The human-readable notification text (Claude Code sets .message).
NOTE=$(jq -r '.message // "Claude needs your attention."' <<<"$IN")
[ -z "$NOTE" ] && exit 0
MSG="⚠️ ${NOTE}"

if [ -n "$GID" ]; then
  # Global mode: only opted-in sessions post; label with the cwd leaf.
  command -v optin_has >/dev/null 2>&1 && optin_has "$SID" || exit 0
  CWD=$(jq -r '.cwd // ""' <<<"$IN")
  [ -z "$CWD" ] && CWD="$PWD"
  LEAF=$(basename "$CWD")
  MSG="${LEAF}:
${MSG}"
  # Shared room is outbound-only under the EMPTY server session key.
  ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
  "$DIR/bot.sh" bot_send "" "$ARGS" >/dev/null 2>&1 &
  exit 0
fi

# Default mode: only the session that ran /bot posts, to its own room.
BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"
[ -f "$BINDING" ] || exit 0
[ "$(jq -r '.session_id // ""' "$BINDING")" = "$SID" ] || exit 0
ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
"$DIR/bot.sh" bot_send "$SID" "$ARGS" >/dev/null 2>&1 &
exit 0
