#!/bin/bash
# Find Claude Code session transcripts for a given project directory.
# Claude stores transcripts under ~/.claude/projects/<encoded-path>/*.jsonl,
# where <encoded-path> is the absolute path with every non-alphanumeric
# character replaced by '-'.
#
# Usage: find-session.sh <project-dir>
# Prints session .jsonl paths, newest first (one per line). Exit 1 if none.

set -euo pipefail

DIR="${1:?usage: find-session.sh <project-dir>}"
DIR=$(cd "$DIR" 2>/dev/null && pwd) || { echo "error: directory not found: $1" >&2; exit 2; }

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
ENCODED=$(printf '%s' "$DIR" | sed 's/[^a-zA-Z0-9]/-/g')
PROJECT_DIR="$CLAUDE_HOME/projects/$ENCODED"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "no-session: $PROJECT_DIR does not exist" >&2
    exit 1
fi

# Newest first; skip empty files.
FOUND=$(find "$PROJECT_DIR" -maxdepth 1 -name '*.jsonl' -size +0c -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2-)

if [ -z "$FOUND" ]; then
    echo "no-session: no transcripts under $PROJECT_DIR" >&2
    exit 1
fi

echo "$FOUND"
