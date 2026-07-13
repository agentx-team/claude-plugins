#!/usr/bin/env bash
# pull.sh — bring the vault up to date BEFORE any read or write ("pull-first").
#
# Mode comes from wiki.json (`sync` field; see locate-vault.sh):
#
#   "git" (default)      — native `git pull --ff-only` (falls back to
#                          fetch + reset when the local branch diverged and the
#                          tree is clean). This is the plain Claude Code /
#                          local-clone mode: logs recorded on other devices
#                          arrive here before you read or append.
#   "save_document"      — AgentX chat mode: the platform ALREADY pulls the
#                          document from git at turn start (backend PullItem,
#                          incremental) and re-materializes the workdir copy.
#                          This script just verifies the checkout exists and
#                          reports its freshness; if the vault dir is a real
#                          git checkout it also prints the local HEAD so the
#                          agent can mention what version it is reading.
#
# Usage: pull.sh
# Exit 0 = vault is as fresh as we can make it; non-zero = vault missing.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
VAULT="$("$SCRIPT_DIR/locate-vault.sh")" || { echo "[wiki-pull] cannot locate vault" >&2; exit 1; }

# Resolve sync mode (same lookup as sync.sh).
read_sync_mode() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" <<'PY' 2>/dev/null
import json, sys
print((json.load(open(sys.argv[1])) or {}).get("sync", ""), end="")
PY
}
sync_mode="${WIKI_SYNC_MODE:-}"
if [[ -z "$sync_mode" ]]; then
  candidates=("$PWD/.config/skills/wiki/wiki.json")
  d="$VAULT"
  while [[ "$d" != "/" ]]; do
    candidates+=("$d/.config/skills/wiki/wiki.json")
    d="$(dirname "$d")"
  done
  candidates+=("$HOME/.config/skills/wiki/wiki.json")
  for cfg in "${candidates[@]}"; do
    m="$(read_sync_mode "$cfg" || true)"
    if [[ -n "$m" ]]; then sync_mode="$m"; break; fi
    [[ -f "$cfg" ]] && { sync_mode="git"; break; }
  done
fi
sync_mode="${sync_mode:-git}"

if [[ "$sync_mode" == "save_document" ]]; then
  # Platform mode: the runtime pulled + re-materialized this doc at turn start.
  head=""
  if git -C "$VAULT" rev-parse HEAD >/dev/null 2>&1; then
    head="$(git -C "$VAULT" rev-parse --short HEAD)"
  fi
  echo "[wiki-pull] mode=save_document — platform pulled this document at turn start."
  [[ -n "$head" ]] && echo "[wiki-pull] vault checkout HEAD: $head"
  exit 0
fi

# git mode: real pull.
cd "$VAULT" || { echo "[wiki-pull] cannot cd to $VAULT" >&2; exit 1; }
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[wiki-pull] vault is not a git repo — nothing to pull."
  exit 0
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "[wiki-pull] no 'origin' remote — local-only vault."
  exit 0
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
before="$(git rev-parse --short HEAD)"
if out="$(git pull --ff-only origin "$BRANCH" 2>&1)"; then
  after="$(git rev-parse --short HEAD)"
  if [[ "$before" == "$after" ]]; then
    echo "[wiki-pull] already up to date ($after)"
  else
    echo "[wiki-pull] updated $before → $after"
    git --no-pager log --oneline "$before..$after" | head -10 | sed 's/^/[wiki-pull]   /'
  fi
  exit 0
fi

# ff-only failed: local commits diverged (e.g. a sync.sh push raced). With a
# CLEAN tree we can rebase our unpushed commits; a dirty tree is left alone so
# uncommitted user edits are never destroyed — sync.sh will reconcile on push.
if [[ -z "$(git status --porcelain)" ]]; then
  if git pull --rebase origin "$BRANCH" >/dev/null 2>&1; then
    echo "[wiki-pull] rebased local commits onto origin/$BRANCH ($(git rev-parse --short HEAD))"
    exit 0
  fi
  git rebase --abort >/dev/null 2>&1 || true
fi
echo "[wiki-pull] WARN: could not fast-forward (local changes/divergence) — proceeding with local state; sync.sh will reconcile on next push." >&2
exit 0
