#!/usr/bin/env bash
# SessionStart: export the real Claude session id so /bot-notify:bot and the
# Stop/Notification hooks target the same opt-in marker. Nothing else — the
# plugin stays completely inert until the user explicitly runs
# /bot-notify:bot (no network call, no context injected, zero tokens).
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id' <<<"$IN")
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export BOT_SESSION_ID=$SID" >> "$CLAUDE_ENV_FILE"
fi
exit 0
