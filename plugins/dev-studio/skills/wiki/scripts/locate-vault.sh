#!/usr/bin/env bash
# locate-vault.sh — print the absolute path of the wiki vault root.
#
# The skill no longer needs to live INSIDE the vault. The vault is bound via a
# small config file `wiki.json`, resolved in this order (first hit wins):
#
#   1. $WIKI_VAULT_PATH env override, if set and valid.
#   2. $PWD/.config/skills/wiki/wiki.json        (per-workspace binding)
#   3. ~/.config/skills/wiki/wiki.json           (per-user default binding)
#   4. Legacy in-vault mode: if this script's REAL location (symlinks resolved)
#      is inside a git repo that carries a `.wiki-vault` marker, that repo root
#      is the vault (backwards compatible with the old vendored layout).
#
# wiki.json shape (generic — works in AgentX chat workdirs AND plain local
# Claude Code):
#   {
#     "version": 1,
#     "vault": "documents/wiki",        // absolute, ~-prefixed, or relative to
#                                       // the dir that CONTAINS .config/
#     "sync": "save_document",          // "save_document" (AgentX chat) | "git"
#     "document": {                     // optional AgentX binding metadata
#       "id": "<library doc id>", "dir": "wiki", "title": "我的个人知识系统"
#     }
#   }
#
# Prints the vault path to stdout, or an error to stderr + exit 1 when no
# binding exists (callers should then say the wiki skill is not bound to any
# vault/document and offer to bind one).
set -euo pipefail

CONFIG_REL=".config/skills/wiki/wiki.json"

# --- resolve this script's real path, following symlinks (portable) ---
resolve_self() {
  local src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir; dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    src="$(readlink "$src")"
    [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# read_vault <wiki.json path> — print resolved vault path or nothing.
read_vault() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 1
  local vault
  # Minimal JSON extraction without a jq dependency (python3 is ubiquitous).
  vault="$(python3 - "$cfg" <<'PY' 2>/dev/null || true
import json, sys
try:
    print((json.load(open(sys.argv[1])) or {}).get("vault", ""))
except Exception:
    pass
PY
)"
  [[ -n "$vault" ]] || return 1
  # ~ expansion
  [[ "$vault" == "~"* ]] && vault="${HOME}${vault:1}"
  # Relative → relative to the dir that contains .config/ (cfg's ../../../..)
  if [[ "$vault" != /* ]]; then
    local base; base="$(cd "$(dirname "$cfg")/../../.." >/dev/null 2>&1 && pwd)"
    vault="$base/$vault"
  fi
  if [[ -d "$vault" ]]; then
    (cd "$vault" >/dev/null 2>&1 && pwd)
    return 0
  fi
  return 1
}

# 1. explicit override
if [[ -n "${WIKI_VAULT_PATH:-}" && -d "$WIKI_VAULT_PATH" ]]; then
  echo "$WIKI_VAULT_PATH"; exit 0
fi

# 2. workspace-local binding (cwd)
if v="$(read_vault "$PWD/$CONFIG_REL")"; then
  echo "$v"; exit 0
fi

# 3. per-user binding
if v="$(read_vault "$HOME/$CONFIG_REL")"; then
  echo "$v"; exit 0
fi

# 4. cwd is (inside) a vault: walk up from $PWD for a .wiki-vault marker.
dir="$PWD"
while [[ "$dir" != "/" ]]; do
  [[ -f "$dir/.wiki-vault" ]] && { echo "$dir"; exit 0; }
  dir="$(dirname "$dir")"
done

# 5. legacy in-vault mode (skill vendored inside the vault repo)
SELF_DIR="$(resolve_self)"
if command -v git >/dev/null 2>&1; then
  if top="$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
    if [[ -n "$top" && -f "$top/.wiki-vault" ]]; then
      echo "$top"; exit 0
    fi
  fi
fi
# marker-file walk-up (legacy)
dir="$SELF_DIR"
while [[ "$dir" != "/" ]]; do
  [[ -f "$dir/.wiki-vault" ]] && { echo "$dir"; exit 0; }
  dir="$(dirname "$dir")"
done

echo "wiki: no vault bound — create $CONFIG_REL (or ~/$CONFIG_REL) with {\"vault\": \"<path>\"}" >&2
exit 1
