#!/usr/bin/env bash
# SessionStart: export the real Claude session id so /bot and the Stop hook
# target the same binding. Nothing else — the plugin stays completely inert
# until the user explicitly runs /bot (no binding, no network, no context
# injected). This holds in BOTH default and global-room mode: global mode only
# changes WHICH room /bot binds to (a shared one), not WHEN posting starts.
set -euo pipefail
IN=$(cat)
SID=$(jq -r '.session_id' <<<"$IN")
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export BOT_SESSION_ID=$SID" >> "$CLAUDE_ENV_FILE"
fi
exit 0
