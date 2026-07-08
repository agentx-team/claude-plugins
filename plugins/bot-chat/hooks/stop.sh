#!/usr/bin/env bash
# Stop: when a turn finishes, push the last assistant message to the bound room.
# Gated on .claude/.bot-binding.json (written by /bot) and on the session id
# matching, so other sessions in the same project don't cross-post.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id' <<<"$IN")

BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"
[ -f "$BINDING" ] || exit 0
[ "$(jq -r '.session_id // ""' "$BINDING")" = "$SID" ] || exit 0

MSG=$(jq -r '.last_assistant_message // ""' <<<"$IN")
[ -z "$MSG" ] && exit 0

ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
"$CLAUDE_PLUGIN_ROOT/scripts/bot.sh" bot_send "$SID" "$ARGS" >/dev/null 2>&1 &
exit 0
