#!/bin/bash
# Claude Code SessionStart hook: load lifecycle context + the plugin's rules.
# SessionStart stdout is added to Claude's context (no model tokens are spent
# generating it). Rules live in ${CLAUDE_PLUGIN_ROOT}/rules/ — the plugin spec
# has no auto-loaded rules directory, so this hook is the standard way a plugin
# ships always-on guidance.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

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

echo "===================================="
exit 0
