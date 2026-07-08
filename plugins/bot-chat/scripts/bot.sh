#!/usr/bin/env bash
# Shared client for the bot MCP HTTP endpoint (fixed shared URL).
# Connection-level identity/config travels in the X-Config header (built from
# env vars) and is invisible to MCP tool semantics. The body carries only
# session_id + tool-specific args; targetUserId/requireMention MAY be passed
# in args as optional per-call overrides, but these scripts never need to.
#   BOT_ID              (required) bot public id ("axb_…", from /settings/bots)
#   BOT_API_KEY         (required) AgentX API key ("agx_…", from /settings/api-keys)
#   BOT_TARGET_USER_ID  (required for bind) default room peer
#   BOT_REQUIRE_MENTION (optional, default true)
#   BOT_ORG_ID          (optional) org scope → X-Org-Id header; empty = the
#                       bot's own org (Personal org for personal bots)
#   BOT_API_URL         (optional, override for testing)
# Usage: bot.sh <tool> <session_id> [json_args_object]
# Prints the tool's structuredContent JSON to stdout. Non-fatal on any error.
set -euo pipefail

TOOL="$1"; SID="${2:-}"; ARGS="${3:-}"; [ -z "$ARGS" ] && ARGS='{}'

URL="${BOT_API_URL:-https://agentx.nx.run/bots.v1.BotService/McpServer}"
# Missing env details go to stderr only; stdout (prompt-visible via the /bot
# command expansion) carries a generic reason.
if [ -z "${BOT_ID:-}" ] || [ -z "${BOT_API_KEY:-}" ]; then
  echo "bot.sh: BOT_ID/BOT_API_KEY not set" >&2
  echo '{"ok":false,"reason":"not_configured"}'
  exit 0
fi

XCONFIG=$(jq -cn \
  --arg bot "$BOT_ID" \
  --arg tgt "${BOT_TARGET_USER_ID:-}" \
  --argjson rm "${BOT_REQUIRE_MENTION:-true}" \
  '{botId:$bot, targetUserId:$tgt, requireMention:$rm}')

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
