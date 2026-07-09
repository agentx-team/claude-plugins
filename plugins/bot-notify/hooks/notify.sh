#!/usr/bin/env bash
# Notification: forward "Claude needs your input" moments (permission prompts,
# idle waits, MCP elicitation forms, background-agent input requests) to the
# shared room so a human watching the IM chat can jump in. This is the
# mid-turn counterpart to stop.sh's turn-end results — same opt-in gating,
# same cwd-leaf label, same shared room.
#
# Notification hooks cannot block and have no decision control — pure side
# effect. Failures are swallowed; we never disturb the session.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id // ""' <<<"$IN")
DIR="$(dirname "$0")/../scripts"

# shellcheck source=/dev/null
. "$DIR/optin.sh"
optin_has "$SID" || exit 0

NOTE=$(jq -r '.message // "Claude needs your attention."' <<<"$IN")
[ -z "$NOTE" ] && exit 0

CWD=$(jq -r '.cwd // ""' <<<"$IN")
[ -z "$CWD" ] && CWD="$PWD"
LEAF=$(basename "$CWD")
MSG="${LEAF}:
⚠️ ${NOTE}"

ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
"$DIR/bot.sh" bot_send "" "$ARGS" >/dev/null 2>&1 &
exit 0
