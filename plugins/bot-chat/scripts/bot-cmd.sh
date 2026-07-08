#!/usr/bin/env bash
# Router for the /bot slash command. Arg: "<room_name>" | "unbind" | "status" | ""
# On bind, writes .claude/.bot-binding.json — the shared anchor read by the
# Stop hook (outbound push) and the bot-channel poller (inbound).
set -euo pipefail
SID="${BOT_SESSION_ID:?run in a session started with the plugin}"
DIR="$(dirname "$0")"
BINDING="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/.bot-binding.json"
ARG="${1:-status}"

case "$ARG" in
  status)
    R=$("$DIR/bot.sh" bot_status "$SID")
    echo "$R" | jq -r 'if .bound then "BOUND to room \"\(.room_name)\"" else "NOT bound" end'
    ;;
  unbind)
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
