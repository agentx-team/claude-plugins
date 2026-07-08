#!/usr/bin/env bash
# SessionStart: export the session id so /bot and the Stop hook target the
# same binding. All endpoint config lives in .mcp.json — nothing else to load.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id' <<<"$IN")
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export BOT_SESSION_ID=$SID" >> "$CLAUDE_ENV_FILE"
fi
exit 0
