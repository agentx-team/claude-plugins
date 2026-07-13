#!/bin/bash
# Claude Code SessionStart hook: load loop context + the plugin's rules.
# SessionStart stdout is added to Claude's context (no model tokens are spent
# generating it). Rules live in ${CLAUDE_PLUGIN_ROOT}/rules/ — the plugin spec
# has no auto-loaded rules directory, so this hook is the standard way a plugin
# ships always-on guidance. (Forking as a project instead? Copy rules/ to
# .claude/rules/ and Claude Code loads them natively, per-path.)

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "=== Agent Team Scaffold — Session Context ==="

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$BRANCH" ]; then
    echo "Branch: $BRANCH"
    echo ""
    echo "Recent commits:"
    git log --oneline -5 2>/dev/null | while read -r line; do echo "  $line"; done
fi

# Loop reminder — the core skeleton of this scaffold.
echo ""
echo "Loop: Planner → Design-Evaluator(APPROVE/REVISE) → Generator → Evaluator(PASS/FAIL) → Package"
echo "Run /agent-team:start to begin, or /agent-team:status to see loop state."
echo "Plugin: agents are namespaced /agent-team:* ; 'cma-check' validates the manifest; the"
echo "        watch-out monitor announces ./out/ packages awaiting sign-off."

# Rules — always-on guardrails shipped with the plugin.
if [ -d "$PLUGIN_ROOT/rules" ]; then
    for rule in "$PLUGIN_ROOT"/rules/*.md; do
        [ -f "$rule" ] || continue
        echo ""
        echo "--- rule: $(basename "$rule") ---"
        # Strip the YAML frontmatter (paths: scoping) — context injection is always-on.
        awk 'BEGIN{fm=0} NR==1&&/^---$/{fm=1;next} fm==1&&/^---$/{fm=2;next} fm!=1{print}' "$rule"
    done
fi

# Outputs staged for human sign-off
if [ -d "out" ]; then
    PKGS=$(find out -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    [ "$PKGS" -gt 0 ] && echo "Awaiting sign-off: $PKGS package(s) under ./out/"
fi

echo "============================================="
exit 0
