#!/bin/bash
# Background monitor (plugin `experimental.monitors`): announce packages that
# land under ./out/ awaiting human sign-off. Each stdout line is delivered to
# Claude as a notification. Runs as a persistent process for the session.
#
# Polls instead of relying on inotify so it works the same on macOS and Linux.
# Project-relative ./out/ is the resolver/packager's surface (see .claude/rules).

OUT_DIR="${CLAUDE_PROJECT_DIR:-.}/out"
SEEN="$(mktemp 2>/dev/null || echo /tmp/agent-team-watch-out.seen)"
: > "$SEEN"

while true; do
    if [ -d "$OUT_DIR" ]; then
        # top-level package dirs under ./out/ (one per deliverable)
        find "$OUT_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r pkg; do
            if ! grep -qxF "$pkg" "$SEEN" 2>/dev/null; then
                echo "$pkg" >> "$SEEN"
                echo "📦 New deliverable staged for sign-off: $(basename "$pkg") (./out/$(basename "$pkg"))"
            fi
        done
    fi
    sleep 15
done
