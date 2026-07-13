#!/bin/bash
# Claude Code SessionStart hook: load project context at session start.
# Input schema (SessionStart): no stdin input.

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

# Outputs staged for human sign-off
if [ -d "out" ]; then
    PKGS=$(find out -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    [ "$PKGS" -gt 0 ] && echo "Awaiting sign-off: $PKGS package(s) under ./out/"
fi

echo "============================================="
exit 0
