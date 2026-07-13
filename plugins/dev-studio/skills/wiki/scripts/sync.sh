#!/usr/bin/env bash
# sync.sh — persist wiki vault changes after every write.
#
# Sync mode comes from wiki.json (`sync` field; see locate-vault.sh):
#
#   "git" (default)      — stage everything, commit, push to origin, surviving
#                          concurrent multi-device pushes (remote-wins merge).
#                          This is the plain Claude Code / local-clone mode.
#   "save_document"      — AgentX chat mode: the vault is a credential-free git
#                          checkout materialized from the Library; pushing is
#                          impossible from here. This script does NOT commit;
#                          it prints a marker instructing the AGENT to call the
#                          `save_document` tool (git-first commit via the
#                          platform, attributed to the user). The skill's
#                          collection step (§7) treats that marker as "now call
#                          save_document with this message".
#
# Usage: sync.sh ["optional commit message"]
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
VAULT="$("$SCRIPT_DIR/locate-vault.sh")" || { echo "[wiki-sync] cannot locate vault" >&2; exit 1; }

MSG="${1:-record: $(date '+%Y-%m-%d %H:%M')}"

# ── Resolve sync mode from wiki.json ──────────────────────────────────────────
# Look where locate-vault.sh looks: cwd, then walking up from the vault (the
# binding usually lives in the workspace that CONTAINS the vault), then ~.
read_sync_mode() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" <<'PY' 2>/dev/null
import json, sys
m = (json.load(open(sys.argv[1])) or {}).get("sync", "")
print(m if m else "", end="")
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
    # A wiki.json without `sync` still binds the vault; default is git mode.
    [[ -f "$cfg" ]] && { sync_mode="git"; break; }
  done
fi
sync_mode="${sync_mode:-git}"

if [[ "$sync_mode" == "save_document" ]]; then
  # AgentX chat mode: no local commits, no push. Tell the agent what to do.
  doc_dir="$(basename "$VAULT")"
  echo "[wiki-sync] mode=save_document — do NOT git commit/push here."
  echo "[wiki-sync] NEXT STEP FOR THE AGENT: call the save_document tool now with:"
  echo "[wiki-sync]   doc_dir: \"$doc_dir\""
  echo "[wiki-sync]   message: \"$MSG\""
  exit 0
fi

# ── git mode (default): commit + remote-wins push with bounded retry ─────────
cd "$VAULT" || { echo "[wiki-sync] cannot cd to $VAULT" >&2; exit 1; }
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# 1. Commit local changes (if any). We may still need to pull even when clean,
#    so don't exit early on a clean tree — only skip the commit.
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git commit -m "$MSG" >/dev/null 2>&1 && echo "[wiki-sync] committed: $MSG" \
    || echo "[wiki-sync] nothing to commit after add"
fi

# No remote → local-only commit, done.
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "[wiki-sync] no 'origin' remote — committed locally only."
  exit 0
fi

# reconcile_remote_wins: merge origin/$BRANCH into HEAD, resolving every conflict
# in favor of the remote, leaving a clean committed state to push.
reconcile_remote_wins() {
  git fetch -q origin "$BRANCH" || return 1
  # -X theirs auto-resolves text conflicts toward the remote (the merged-in side).
  if git merge --no-edit -X theirs "origin/$BRANCH" >/dev/null 2>&1; then
    return 0
  fi
  # Structural conflicts (modify/delete, rename) that -X theirs can't auto-resolve:
  # force every remaining conflicted path to the remote version, then commit.
  echo "[wiki-sync] reconciling residual conflicts (remote wins)…" >&2
  git checkout --theirs -- . >/dev/null 2>&1 || true
  git diff --name-only --diff-filter=U -z 2>/dev/null | while IFS= read -r -d '' f; do
    git rm -f --ignore-unmatch -- "$f" >/dev/null 2>&1 || true
  done
  git add -A
  git commit --no-edit >/dev/null 2>&1 || git commit -m "merge origin/$BRANCH (remote wins)" >/dev/null 2>&1
  git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && { git merge --abort >/dev/null 2>&1; return 1; }
  return 0
}

# 2. Push with bounded retry; reconcile on rejection.
for attempt in 1 2 3 4 5; do
  if git push -q origin "$BRANCH" 2>/dev/null; then
    echo "[wiki-sync] pushed to origin/$BRANCH"
    exit 0
  fi
  echo "[wiki-sync] push rejected (remote advanced); reconciling (attempt $attempt)…" >&2
  if ! reconcile_remote_wins; then
    echo "[wiki-sync] WARN: reconcile failed on attempt $attempt; retrying fetch…" >&2
    git fetch -q origin "$BRANCH" 2>/dev/null || true
  fi
done

# 3. Last resort: report. Local commit is safe; next sync will retry.
echo "[wiki-sync] WARN: could not push after 5 attempts (committed locally; will sync next time)." >&2
exit 0
