#!/bin/bash
# Claude Code SessionStart hook: load project context at session start.
# Input schema (SessionStart): no stdin input.

echo "=== dev-studio — Session Context ==="

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$BRANCH" ]; then
    echo "Branch: $BRANCH"
    echo ""
    echo "Recent commits:"
    git log --oneline -5 2>/dev/null | while read -r line; do echo "  $line"; done
fi

# Lifecycle reminder — the skeleton of this studio.
echo ""
echo "Lifecycle: deliver(planner→engineer→reviewer) → ship(operator→reviewer)"
echo "           → [human deploys] → accept(e2e-tester, black-box) → promote(marketer→reviewer)"
echo "Cloud-native: proto-first APIs, scaffold template (github.com/aws300/scaffold),"
echo "              cluster platform stack (Prometheus/Loki/Tempo/Grafana, Temporal)."
echo "Run /dev-studio:start to begin, or /dev-studio:status to see lifecycle state."

# Outputs staged for human sign-off
if [ -d "out" ]; then
    PKGS=$(find out -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    [ "$PKGS" -gt 0 ] && echo "Awaiting sign-off: $PKGS package(s) under ./out/"
fi

echo "===================================="
exit 0
