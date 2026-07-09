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
# Prints the tool's structuredContent JSON to stdout. Non-fatal on any error:
# failures come back as {ok:false, reason:<category>, detail:<original error>,
# http_status?} — reason is a stable machine key, detail carries the raw
# server/curl error text (truncated) for humans.
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

# fail() prints a structured error and exits 0 (callers treat stdout as the
# result; never fail the calling hook). detail is raw error text, truncated.
fail() { # $1=reason $2=detail [$3=http_status]
  jq -cn --arg r "$1" --arg d "${2:0:500}" --arg s "${3:-}" \
    '{ok:false, reason:$r, detail:$d} + (if $s != "" then {http_status:($s|tonumber)} else {} end)'
  exit 0
}

CURL_ERR=$(mktemp); trap 'rm -f "$CURL_ERR"' EXIT
# -w appends the HTTP status as the last line; body stays on the lines above.
RAW=$(curl -sS -m 10 -w '\n%{http_code}' -X POST "$URL" \
  -H "Authorization: Bearer $BOT_API_KEY" \
  -H "X-Config: $XCONFIG" \
  "${ORG_HEADER[@]}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$BODY" 2>"$CURL_ERR") || fail network "$(cat "$CURL_ERR")"

HTTP_STATUS="${RAW##*$'\n'}"
RESP="${RAW%$'\n'*}"

jq -e . >/dev/null 2>&1 <<<"$RESP" \
  || fail parse "HTTP $HTTP_STATUS, non-JSON body: $RESP" "$HTTP_STATUS"

# Prefer the tool's structuredContent; otherwise surface the ORIGINAL error —
# JSON-RPC .error.message (auth/routing failures) or the tool's text content —
# under a reason that says which layer failed.
SC=$(jq -c '.result.structuredContent // empty' <<<"$RESP")
[ -n "$SC" ] && { printf '%s\n' "$SC"; exit 0; }

RPC_ERR=$(jq -r '.error.message // empty' <<<"$RESP")
[ -n "$RPC_ERR" ] && fail rpc_error "$RPC_ERR" "$HTTP_STATUS"

TOOL_TEXT=$(jq -r '.result.content[0].text // empty' <<<"$RESP")
fail bad_response "${TOOL_TEXT:-$RESP}" "$HTTP_STATUS"
