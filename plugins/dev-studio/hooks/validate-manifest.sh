#!/bin/bash
# Claude Code PostToolUse hook (Write|Edit): keep the CMA manifest honest.
# When an agent/workflow/skill/manifest file changes, re-run the CMA check so a
# broken reference (missing specialist md, dangling skill, bad schema) is caught
# immediately rather than at deploy time. Non-blocking: warns, never fails the edit.

INPUT=$(cat)

# Extract the edited path (best-effort; works with or without jq).
if command -v jq >/dev/null 2>&1; then
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
else
    FILE=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Prefer the plugin's own validator when running as an installed plugin
# (${CLAUDE_PLUGIN_ROOT} is set); fall back to the repo-relative path locally.
CHECK="scripts/cma/check.py"
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/cma/check.py" ] && CHECK="${CLAUDE_PLUGIN_ROOT}/scripts/cma/check.py"

case "$FILE" in
    *agents/*|*skills/*|*scripts/cma/*)
        if command -v python3 >/dev/null 2>&1 && [ -f "$CHECK" ]; then
            OUT=$(python3 "$CHECK" 2>&1)
            if [ $? -ne 0 ]; then
                echo "[validate-manifest] CMA check reported issues:" >&2
                echo "$OUT" >&2
            fi
        fi
        ;;
esac
exit 0
