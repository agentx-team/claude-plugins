#!/bin/bash
# Claude Code PostToolUse hook: when an agent/workflow md, the manifest, or a
# schema changes, advise re-running the CMA validator. Advisory only (exit 0).
# Input schema (PostToolUse for Write|Edit):
# { "tool_name": "Write", "tool_input": { "file_path": "...", "content": "..." } }

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
else
    FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi
FILE_PATH=$(echo "$FILE_PATH" | sed 's|\\|/|g')

# Only act on files that affect the CMA build surface.
if echo "$FILE_PATH" | grep -qE '(agents/.*\.md|scripts/cma/cma\.yaml|scripts/cma/schemas/.*\.json|skills/.*/SKILL\.md)$'; then
    # Prefer the plugin's own validator when running as an installed plugin
    # (${CLAUDE_PLUGIN_ROOT} is set); fall back to the repo-relative path locally.
    CHECK="scripts/cma/check.py"
    [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/cma/check.py" ] && CHECK="${CLAUDE_PLUGIN_ROOT}/scripts/cma/check.py"
    echo "=== CMA surface changed: $(basename "$FILE_PATH") ===" >&2
    echo "Run 'python3 ${CHECK}' to validate manifest references, skills, and no nesting." >&2
    echo "=================================================" >&2
fi

exit 0
