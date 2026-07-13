#!/usr/bin/env python3
"""Extract a readable digest from a Claude Code session transcript (.jsonl).

Transcripts under ~/.claude/projects/<encoded>/<uuid>.jsonl mix many record
types (user, assistant, attachment, file-history-snapshot, ...). This pulls
out just the conversation: user prompts, assistant text, and the tools the
assistant touched — enough for a new session to absorb the history without
re-reading megabytes of raw JSONL.

Usage:
    extract-session.py <session.jsonl> [--max-chars N] [--full]

--max-chars caps total output (default 60000; oldest turns are elided first).
--full disables per-message truncation.
Only stdlib is used.
"""
import argparse
import json
import sys

PER_MSG = 1500  # per-message char cap unless --full


def block_text(content, full):
    """Flatten a message's content (str or block list) into display text."""
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts = []
    for b in content:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t == "text":
            parts.append(b["text"].strip())
        elif t == "tool_use":
            name = b.get("name", "?")
            inp = b.get("input", {})
            hint = (inp.get("file_path") or inp.get("command")
                    or inp.get("pattern") or inp.get("description") or "")
            if isinstance(hint, str) and hint:
                hint = hint.replace("\n", " ")[:120]
                parts.append(f"[tool: {name} — {hint}]")
            else:
                parts.append(f"[tool: {name}]")
        # thinking / tool_result blocks are skipped: bulky, low signal
    return "\n".join(p for p in parts if p)


def is_real_user(rec):
    """True for actual user prompts (not tool results echoed as user turns)."""
    content = rec.get("message", {}).get("content")
    if isinstance(content, str):
        return not content.startswith("<")
    if isinstance(content, list):
        return any(isinstance(b, dict) and b.get("type") == "text" for b in content)
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("--max-chars", type=int, default=60000)
    ap.add_argument("--full", action="store_true")
    args = ap.parse_args()

    turns = []  # (role, text)
    cwd = None
    with open(args.transcript, errors="replace") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = rec.get("type")
            if t not in ("user", "assistant"):
                continue
            if rec.get("isSidechain") or rec.get("isMeta"):
                continue
            cwd = rec.get("cwd") or cwd
            if t == "user" and not is_real_user(rec):
                continue
            text = block_text(rec.get("message", {}).get("content"), args.full)
            if not text:
                continue
            if not args.full and len(text) > PER_MSG:
                text = text[:PER_MSG] + " …[truncated]"
            # merge consecutive same-role turns (streaming splits assistant output)
            if turns and turns[-1][0] == t:
                turns[-1] = (t, turns[-1][1] + "\n" + text)
            else:
                turns.append((t, text))

    if not turns:
        print("no conversation content found in transcript", file=sys.stderr)
        sys.exit(1)

    header = (f"# Session digest: {args.transcript}\n"
              f"Original working directory: {cwd or 'unknown'}\n"
              f"Turns: {len(turns)}\n")
    rendered = [f"\n## {'User' if r == 'user' else 'Assistant'}\n{txt}"
                for r, txt in turns]

    # Trim oldest turns first if over budget; keep the tail (most recent work).
    body = "".join(rendered)
    dropped = 0
    while len(header) + len(body) > args.max_chars and len(rendered) > 2:
        rendered.pop(0)
        dropped += 1
        body = "".join(rendered)
    if dropped:
        header += f"(elided {dropped} oldest turns to fit budget)\n"

    print(header + body)


if __name__ == "__main__":
    main()
