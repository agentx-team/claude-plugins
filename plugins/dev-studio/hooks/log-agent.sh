#!/bin/bash
# Claude Code SubagentStart hook: log agent invocations for an audit trail.
# Input schema (SubagentStart): { "session_id": "...", "agent_id": "...", "agent_type": "..." }
# NOTE: the agent name is in `agent_type`, NOT `agent_name`.

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null)
else
    AGENT_NAME=$(echo "$INPUT" | grep -oE '"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"agent_type"[[:space:]]*:[[:space:]]*"//;s/"$//')
    [ -z "$AGENT_NAME" ] && AGENT_NAME="unknown"
fi

LOG_DIR="out/session-logs"
mkdir -p "$LOG_DIR" 2>/dev/null
echo "$(date +%Y%m%d_%H%M%S) | Agent invoked: $AGENT_NAME" >> "$LOG_DIR/agent-audit.log" 2>/dev/null
exit 0
