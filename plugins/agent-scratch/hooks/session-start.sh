#!/bin/bash
# Claude Code SessionStart hook: rescan ~/.claude at every session start so
# the session begins knowing which skills / plugins / agents / commands exist.
# Brief mode keeps the injected context small; run /scratch:fresh for detail.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "=== Agent Scratch — capability snapshot ==="
bash "$PLUGIN_ROOT/scripts/scan-claude-home.sh" --brief
echo ""
echo "Commands: /scratch:fresh (rescan + clone project into ./projects/<name>) · /scratch:takeover <dir> (absorb another directory's session + mv it into ./projects/<name>)"
echo "Convention: always clone git projects into ./projects/<repo> (never the cwd root), and moved-in projects land under ./projects/<name>."
echo "==========================================="
exit 0
