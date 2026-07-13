#!/bin/bash
# Rescan ~/.claude and print a capability inventory: skills, plugins, agents,
# commands, MCP servers, output styles. Read-only; safe to run at any time.
# Usage: scan-claude-home.sh [--brief]

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
BRIEF=0
[ "$1" = "--brief" ] && BRIEF=1

echo "=== Claude Home Inventory ($CLAUDE_HOME) ==="

# --- Skills: every */SKILL.md, name + first line of description -------------
if [ -d "$CLAUDE_HOME/skills" ]; then
    # trailing slash: follow a possible symlink at the skills dir itself
    COUNT=$(find -L "$CLAUDE_HOME/skills/" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l)
    echo ""
    echo "## Skills ($COUNT)"
    if [ "$BRIEF" -eq 1 ]; then
        find -L "$CLAUDE_HOME/skills/" -maxdepth 2 -name SKILL.md -printf '%h\n' 2>/dev/null \
            | xargs -rn1 basename | sort | paste -sd, - | sed 's/,/, /g'
    else
        find -L "$CLAUDE_HOME/skills/" -maxdepth 2 -name SKILL.md 2>/dev/null | sort | while read -r f; do
            name=$(basename "$(dirname "$f")")
            desc=$(awk -F': *' '/^description:/{print $2; exit}' "$f" | cut -c1-100)
            echo "- $name${desc:+ — $desc}"
        done
    fi
fi

# --- Plugins: installed_plugins.json ----------------------------------------
if [ -f "$CLAUDE_HOME/plugins/installed_plugins.json" ]; then
    echo ""
    echo "## Plugins"
    python3 - "$CLAUDE_HOME/plugins/installed_plugins.json" <<'EOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    for name, installs in data.get("plugins", {}).items():
        for i in installs:
            print(f"- {name} v{i.get('version','?')} (scope: {i.get('scope','?')})")
except Exception as e:
    print(f"  (could not parse: {e})")
EOF
fi

# --- User-level agents and commands ------------------------------------------
for kind in agents commands; do
    if [ -d "$CLAUDE_HOME/$kind" ]; then
        COUNT=$(find -L "$CLAUDE_HOME/$kind/" -name '*.md' 2>/dev/null | wc -l)
        [ "$COUNT" -gt 0 ] || continue
        echo ""
        echo "## User $kind ($COUNT)"
        find -L "$CLAUDE_HOME/$kind/" -name '*.md' 2>/dev/null | sort | while read -r f; do
            echo "- $(basename "$f" .md)"
        done
    fi
done

# --- MCP servers from user settings ------------------------------------------
if [ -f "$CLAUDE_HOME/settings.json" ]; then
    MCP=$(python3 - "$CLAUDE_HOME/settings.json" <<'EOF'
import json, sys
try:
    s = json.load(open(sys.argv[1]))
    names = list(s.get("mcpServers", {}).keys())
    if names:
        print("\n".join(f"- {n}" for n in names))
except Exception:
    pass
EOF
)
    if [ -n "$MCP" ]; then
        echo ""
        echo "## MCP servers (user settings)"
        echo "$MCP"
    fi
fi

echo ""
echo "=== End of inventory ==="
exit 0
