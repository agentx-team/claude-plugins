#!/usr/bin/env python3
"""build.py — compile md agent assets into Claude Managed Agents (CMA) JSON.

dev-studio — a cloud-native software delivery agent team. Same CMA layer as
agent-team-scaffold: ONE python file + ONE tiny manifest (cma.yaml). Instead of
hand-writing a yaml per agent, this reads the md assets already written for
local Claude Code / Cowork and DERIVES the CMA deploy payload:

  - system prompt  ← the orchestrator/specialist md BODY (frontmatter stripped) + headless_append
  - model          ← cma.yaml `model` (parameterized: ${CMA_MODEL:-sonnet}) or --model
  - tools          ← md frontmatter `tools:` string  → agent_toolset (default-deny + allowlist),
                     further shaped by each leaf's `role` (reader/builder/critic/resolver)
  - skills         ← md frontmatter `skills:[...]`    → resolved to skill dirs under skills/
  - callable_agents← cma.yaml `leaves:` (the orchestration topology — the only thing
                     that can't be inferred from md)
  - output_schema  ← cma.yaml leaf `schema:` (only for reader-role leaves)
  - display_name   ← md frontmatter `display_name:` (carried through for UI)

Usage:
  python3 scripts/cma/build.py                 # dry-run: print resolved CMA JSON for every workflow
  python3 scripts/cma/build.py deliver-service # dry-run a single workflow
  python3 scripts/cma/build.py --model opus     # override model
  python3 scripts/cma/build.py --post           # upload skills + POST /v1/agents (needs ANTHROPIC_API_KEY)

No third-party deps for dry-run (pure stdlib + pyyaml). --post is a stub
showing where the API calls go; wire it to your deploy flow.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]          # repo root = dev-studio/
CMA_DIR = Path(__file__).resolve().parent
MANIFEST = CMA_DIR / "cma.yaml"

# role → which file tools the leaf gets. Tools are the task boundary:
# only builder/resolver ever get write access.
ROLE_TOOLS = {
    "reader":      ["read", "grep"],                          # untrusted input; NO write, NO mcp
    "critic":      ["read", "grep", "glob"],                  # read-only verdict — the Evaluators
    "builder":     ["read", "grep", "glob", "write", "edit"], # writes a scoped surface, e.g. src/
    "resolver":    ["read", "write", "edit"],                 # the ONLY worker that writes ./out/
    "orchestrator":["read", "grep", "glob"],                  # dispatch/aggregate; never writes
    "tester":      [],                                        # BLACK-BOX: NO repo file tools at all —
                                                              # judges DEPLOYED artifacts via web tools
                                                              # only (product / API / Grafana URLs). Never
                                                              # sees source. Declares websearch/webfetch
                                                              # in its md `tools:` (granted additively).
}

# web tools are read-only (no filesystem write), so they're safe to grant on top
# of any non-resolver role when the agent's md frontmatter declares them.
_WEB_TOOL_MAP = {"websearch": "websearch", "webfetch": "webfetch"}


# ── minimal YAML reader ──────────────────────────────────────────────────────
def _load_yaml(text: str):
    try:
        import yaml
        return yaml.safe_load(text)
    except Exception:
        pass
    raise SystemExit("pyyaml required: pip install pyyaml")


def _expand_env(s: str) -> str:
    """Expand ${VAR} and ${VAR:-default} in a string."""
    def repl(m):
        var, default = m.group(1), m.group(3)
        return os.environ.get(var, default if default is not None else m.group(0))
    return re.sub(r"\$\{([A-Z0-9_]+)(:-([^}]*))?\}", repl, s)


def parse_frontmatter(md_text: str):
    """Return (frontmatter_dict, body) from a markdown file."""
    if md_text.startswith("---"):
        end = md_text.find("\n---", 3)
        if end != -1:
            fm = _load_yaml(md_text[3:end]) or {}
            body = md_text[end + 4:].lstrip("\n")
            return fm, body
    return {}, md_text


def tools_to_toolset(tool_names):
    """A list of file-tool names → the CMA agent_toolset_20260401 structure."""
    return [{
        "type": "agent_toolset_20260401",
        "default_config": {"enabled": False},
        "configs": [{"name": n, "enabled": True} for n in tool_names],
    }]


def find_skill(name: str):
    """Locate a skill dir by name anywhere under skills/."""
    for sm in (REPO / "skills").rglob("SKILL.md"):
        if sm.parent.name == name:
            return sm.parent
    return None


def resolve_skills(skill_names):
    """skill name → {type: custom, skill_ref: <path-relative-to-repo>}."""
    out = []
    for nm in skill_names or []:
        d = find_skill(nm)
        if d:
            out.append({"type": "custom", "skill_ref": str(d.relative_to(REPO))})
        else:
            print(f"  ! skill '{nm}' not found under skills/", file=sys.stderr)
    return out


def _web_tools_from_fm(fm: dict, role: str) -> list:
    """Extract WebSearch/WebFetch declared in md frontmatter `tools:` → CMA tool
    names. resolver stays write-only-to-out (no web)."""
    if role == "resolver":
        return []
    raw = fm.get("tools") or ""
    declared = {t.strip().lower() for t in str(raw).replace(",", " ").split()}
    return [v for k, v in _WEB_TOOL_MAP.items() if k in declared]


def build_leaf(leaf: dict, model: str) -> dict:
    """One depth-1 subagent JSON from a cma.yaml leaf entry.

    Supports both 'specialist' (preferred — agents/specialists/ directory) and
    'expert' (original scaffold key) leaf keys.
    """
    role = leaf.get("role", "critic")
    name = leaf["as"]
    md_key = "specialist" if "specialist" in leaf else "expert"
    fm = {}
    if md_key in leaf:
        fm, body = parse_frontmatter((REPO / leaf[md_key]).read_text())
        prompt = body.strip()
        skills = resolve_skills(fm.get("skills"))
    else:
        prompt = (leaf.get("prompt") or "").strip()
        skills = []
    # role sets the base file-tool allowlist; web tools are NOT writes, so a
    # leaf that declares WebSearch/WebFetch in its md frontmatter `tools:` also
    # gets them on the CMA surface (additive).
    tool_names = list(ROLE_TOOLS[role]) + _web_tools_from_fm(fm, role)
    node = {
        "name": name,
        "model": model,
        "system": {"text": prompt},
        "tools": tools_to_toolset(tool_names),
        "mcp_servers": [],
        "skills": skills,
        "callable_agents": [],     # depth-1: leaves never nest (CMA one-level rule)
    }
    if fm.get("display_name"):
        node["display_name"] = fm["display_name"]
    if role == "reader" and leaf.get("schema"):
        node["output_schema"] = json.loads((REPO / leaf["schema"]).read_text())
    return node


def build_workflow(name: str, wf: dict, model: str, headless: str) -> dict:
    """One orchestrator + its leaves → the full CMA payload for POST /v1/agents."""
    fm, body = parse_frontmatter((REPO / wf["orchestrator"]).read_text())
    system = body.strip()
    if headless:
        system += "\n\n" + headless.strip()
    orch = {
        "name": fm.get("name", name),
        "model": model,
        "system": {"text": system},
        "tools": tools_to_toolset(ROLE_TOOLS["orchestrator"]),
        "mcp_servers": [],
        "skills": resolve_skills(fm.get("skills")),
        "callable_agents": [build_leaf(l, model) for l in wf.get("leaves", [])],
    }
    if fm.get("display_name"):
        orch["display_name"] = fm["display_name"]
    return orch


def main(argv):
    do_post = "--post" in argv
    model_override = None
    if "--model" in argv:
        model_override = argv[argv.index("--model") + 1]
    targets = [a for a in argv[1:] if not a.startswith("--") and a != model_override]

    manifest = _load_yaml(MANIFEST.read_text())
    model = model_override or _expand_env(str(manifest.get("model", "sonnet")))
    headless = manifest.get("headless_append", "")
    workflows = manifest.get("workflows", {})
    if targets:
        workflows = {k: v for k, v in workflows.items() if k in targets}

    for name, wf in workflows.items():
        payload = build_workflow(name, wf, model, headless)
        n_leaves = len(payload["callable_agents"])
        writers = [l["name"] for l in payload["callable_agents"]
                   if any(c["name"] in ("write", "edit") for ts in l["tools"] for c in ts["configs"])]
        print(f"\n===== workflow: {name}  (model={model}, leaves={n_leaves}, writers={writers}) =====")
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        if do_post:
            print(f"  [--post] would upload skills + POST /v1/agents for '{name}' "
                  f"(wire to anthropic SDK / deploy here)", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
