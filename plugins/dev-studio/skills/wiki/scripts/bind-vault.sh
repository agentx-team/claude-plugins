#!/usr/bin/env bash
# bind-vault.sh — write the wiki.json binding that associates the wiki skill
# with a vault directory.
#
# Usage:
#   bind-vault.sh <vault-path> [--sync git|save_document] [--doc-id ID]
#                 [--doc-title TITLE] [--global]
#
# Writes $PWD/.config/skills/wiki/wiki.json (or ~/.config/... with --global).
# <vault-path> may be absolute, ~-prefixed, or relative to the cwd; relative
# paths are stored relative so the binding survives workspace relocation.
#
# Examples:
#   # AgentX chat workdir: bind the materialized Library document, save via
#   # the save_document tool (platform git-first commit):
#   bind-vault.sh documents/wiki --sync save_document \
#     --doc-id b3321b1bd8cb77c4ace2044d --doc-title "我的个人知识系统"
#
#   # plain Claude Code, local clone with push access:
#   bind-vault.sh ~/Workspace/knowledge/wiki --sync git --global
set -euo pipefail

VAULT_ARG="${1:-}"
[[ -n "$VAULT_ARG" ]] || { echo "usage: bind-vault.sh <vault-path> [--sync git|save_document] [--doc-id ID] [--doc-title TITLE] [--global]" >&2; exit 1; }
shift

SYNC="git"; DOC_ID=""; DOC_TITLE=""; TARGET_BASE="$PWD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync)      SYNC="${2:-git}"; shift 2 ;;
    --doc-id)    DOC_ID="${2:-}"; shift 2 ;;
    --doc-title) DOC_TITLE="${2:-}"; shift 2 ;;
    --global)    TARGET_BASE="$HOME"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Validate the vault dir exists (resolve for the check, store as given).
CHECK="$VAULT_ARG"
[[ "$CHECK" == "~"* ]] && CHECK="${HOME}${CHECK:1}"
[[ "$CHECK" == /* ]] || CHECK="$PWD/$CHECK"
[[ -d "$CHECK" ]] || { echo "vault dir not found: $CHECK" >&2; exit 1; }

CFG_DIR="$TARGET_BASE/.config/skills/wiki"
mkdir -p "$CFG_DIR"

python3 - "$CFG_DIR/wiki.json" "$VAULT_ARG" "$SYNC" "$DOC_ID" "$DOC_TITLE" "$CHECK" <<'PY'
import json, os, sys
path, vault, sync, doc_id, doc_title, resolved = sys.argv[1:7]
cfg = {"version": 1, "vault": vault, "sync": sync}
if doc_id:
    cfg["document"] = {"id": doc_id, "dir": os.path.basename(resolved)}
    if doc_title:
        cfg["document"]["title"] = doc_title
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"[wiki-bind] wrote {path}")
print(json.dumps(cfg, ensure_ascii=False, indent=2))
PY
