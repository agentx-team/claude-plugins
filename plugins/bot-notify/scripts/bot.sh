#!/usr/bin/env bash
# Shared client for the bot MCP HTTP endpoint (fixed shared URL). bot-notify
# is outbound-only — it never calls bot_receive — so X-Config carries just
# botId + targetUserId (no requireMention: that field only affects inbound
# filtering, which this plugin never performs). Connection-level identity
# travels in the X-Config header (built from env vars), invisible to MCP tool
# semantics; the body carries only session_id + tool-specific args.
#   BOT_ID              (required) bot public id ("axb_…", from /settings/bots)
#   BOT_API_KEY         (required) AgentX API key ("agx_…", from /settings/api-keys)
#   BOT_TARGET_USER_ID  (required for bind) shared room peer
#   BOT_ORG_ID          (optional) org scope → X-Org-Id header
#   BOT_API_URL         (optional, override for testing)
# Usage: bot.sh <tool> <session_id> [json_args_object]
# Prints the tool's structuredContent JSON to stdout. Non-fatal on any error.
set -euo pipefail

TOOL="$1"; SID="${2:-}"; ARGS="${3:-}"; [ -z "$ARGS" ] && ARGS='{}'

URL="${BOT_API_URL:-https://agentx.nx.run/bots.v1.BotService/McpServer}"
# Missing env details go to stderr only; stdout (prompt-visible via the
# /bot-notify:bot command expansion) carries a generic reason.
if [ -z "${BOT_ID:-}" ] || [ -z "${BOT_API_KEY:-}" ]; then
  echo "bot.sh: BOT_ID/BOT_API_KEY not set" >&2
  echo '{"ok":false,"reason":"not_configured"}'
  exit 0
fi

XCONFIG=$(jq -cn --arg bot "$BOT_ID" --arg tgt "${BOT_TARGET_USER_ID:-}" \
  '{botId:$bot, targetUserId:$tgt}')

ARGS=$(jq -c --arg sid "$SID" '. + {session_id:$sid}' <<<"$ARGS")
BODY=$(jq -cn --arg t "$TOOL" --argjson a "$ARGS" \
  '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$t,arguments:$a}}')

ORG_HEADER=()
[ -n "${BOT_ORG_ID:-}" ] && ORG_HEADER=(-H "X-Org-Id: $BOT_ORG_ID")

RESP=$(curl -sS -m 10 -X POST "$URL" \
  -H "Authorization: Bearer $BOT_API_KEY" \
  -H "X-Config: $XCONFIG" \
  "${ORG_HEADER[@]}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$BODY" 2>/dev/null) || { echo '{"ok":false,"reason":"network"}'; exit 0; }

jq -c '.result.structuredContent // {ok:false,reason:"bad_response",raw:(.result.content[0].text // .error.message // "unknown")}' <<<"$RESP" \
  2>/dev/null || echo '{"ok":false,"reason":"parse"}'
