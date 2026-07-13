#!/bin/bash
# Claude Code PreToolUse hook: warn on pushes to protected branches.
# Exit 0 = allow, Exit 2 = block.
# Input schema (PreToolUse for Bash):
# { "tool_name": "Bash", "tool_input": { "command": "git push origin main" } }

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
else
    COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

echo "$COMMAND" | grep -qE '^git[[:space:]]+push' || exit 0

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
for branch in develop main master; do
    if [ "$CURRENT_BRANCH" = "$branch" ] || echo "$COMMAND" | grep -qE "[[:space:]]${branch}([[:space:]]|$)"; then
        echo "Push to protected branch '$branch' detected." >&2
        echo "Reminder: run 'python3 scripts/cma/check.py' and ensure the latest verdict is PASS." >&2
        break
    fi
done

exit 0
