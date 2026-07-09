#!/usr/bin/env bash
# Stop: when a turn finishes, push the last assistant message to the shared
# notification room — but ONLY for sessions that explicitly opted in via
# /bot-notify:bot. All opted-in sessions (possibly on different machines)
# share ONE room, so each message is prefixed with the session's
# working-directory leaf so the reader can tell sessions apart.
#
# Pure shell, zero model tokens: unopted-in sessions make zero network calls.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id' <<<"$IN")
DIR="$(dirname "$0")/../scripts"

# shellcheck source=/dev/null
. "$DIR/optin.sh"
optin_has "$SID" || exit 0

MSG=$(jq -r '.last_assistant_message // ""' <<<"$IN")
[ -z "$MSG" ] && exit 0

CWD=$(jq -r '.cwd // ""' <<<"$IN")
[ -z "$CWD" ] && CWD="$PWD"
LEAF=$(basename "$CWD")
MSG="${LEAF}:
${MSG}"

# The shared room is bound under the EMPTY server session key (see bot-cmd.sh).
ARGS=$(jq -cn --arg t "$MSG" '{text:$t}')
"$DIR/bot.sh" bot_send "" "$ARGS" >/dev/null 2>&1 &
exit 0
