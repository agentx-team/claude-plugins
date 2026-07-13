#!/usr/bin/env python3
"""build.py — compile md agent assets into Claude Managed Agents (CMA) JSON.

The CMA layer is ONE python file + ONE tiny manifest (cma.yaml). Instead of
hand-writing a yaml per agent (like financial-services does), this reads the
md assets you already wrote for local Claude Code / Cowork and DERIVES the CMA
deploy payload:

  - system prompt  ← the orchestrator md BODY (frontmatter stripped) + headless_append
  - model          ← cma.yaml `model` (parameterized: ${CMA_MODEL:-sonnet}) or --model
  - tools          ← md frontmatter `tools:` string  → agent_toolset (default-deny + allowlist),
                     further shaped by each leaf's `role` (reader/builder/critic/resolver)
  - skills         ← md frontmatter `skills:[...]`    → resolved to skill dirs under skills/
  - callable_agents← cma.yaml `leaves:` (the orchestration topology — the only thing
                     that can't be inferred from md)
  - output_schema  ← cma.yaml leaf `schema:` (only for reader-role leaves)
  - session.resources ← cma.yaml `agent.memory/.knowledge` + per-project
                     `memory/.knowledge` + workflow `session_memory:` + per-leaf
                     `memory:` → the memory stores + knowledge docs to attach when
                     the session is created, aggregated across scopes.

Four-layer model (see docs/platform-design.zh.md): Agent -> Project -> Session -> Context.
Memory/knowledge attach at SESSION creation in `resources[]` (mounted /mnt/memory/
and /workspace), NOT on the agent. `scope` (agent|project|session) decides which
sessions share a store. build.py iterates PROJECTS × their workflows and emits, per
(project, workflow): the agent payload (created once, reused) and the session payload
with scope-aware id placeholders the platform substitutes at deploy time:
  scope=agent   → ${MEMSTORE_<KEY>}             (one store, all projects share)
  scope=project → ${MEMSTORE_<KEY>__<PROJECT>}  (one per project, isolated)
  scope=session → ${MEMSTORE_<KEY>__SESSION}    (fresh per session)
Knowledge mirrors this (${FILE_<KEY>...} for files; repo path for github_repository).

Usage:
  python3 scripts/cma/build.py                 # dry-run: print resolved CMA JSON for every workflow
  python3 scripts/cma/build.py combat-feature  # dry-run a single workflow
  python3 scripts/cma/build.py --model opus     # override model
  python3 scripts/cma/build.py --post           # upload skills + POST /v1/agents (needs ANTHROPIC_API_KEY)

No third-party deps for dry-run (pure stdlib + a tiny YAML reader). --post is a stub
showing where the API calls go; wire it to your deploy flow.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]          # repo root
CMA_DIR = Path(__file__).resolve().parent
MANIFEST = CMA_DIR / "cma.yaml"

# role → which file tools the leaf gets. The whole point of preventing task overlap:
# tools are the task boundary. Only `resolver`/`builder` ever get write.
ROLE_TOOLS = {
    "reader":   ["read", "grep"],                  # untrusted input; NO write, NO mcp
    "critic":   ["read", "grep", "glob"],          # read-only verdict
    "builder":  ["read", "grep", "glob", "write", "edit"],   # writes scoped to src/ by prompt
    "resolver": ["read", "write", "edit"],         # the ONLY writer to ./out/
    "orchestrator": ["read", "grep", "glob"],      # dispatch/aggregate; never writes
}


# ── minimal YAML reader (handles the tiny subset cma.yaml / frontmatter use) ──
def _load_yaml(text: str):
    try:
        import yaml  # use real yaml if available
        return yaml.safe_load(text)
    except Exception:
        pass
    # fallback: cma.yaml is intentionally simple; but prefer pyyaml. Fail loud.
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
    """Locate a skill dir by name anywhere under skills/ (skills are organized by category)."""
    for sm in (REPO / "skills").rglob("SKILL.md"):
        if sm.parent.name == name:
            return sm.parent
    return None


def resolve_skills(skill_names):
    """skill name → {type: custom, skill_ref: <path-relative-to-repo>}. Drift-checked elsewhere."""
    out = []
    for nm in skill_names or []:
        d = find_skill(nm)
        if d:
            out.append({"type": "custom", "skill_ref": str(d.relative_to(REPO))})
        else:
            print(f"  ! skill '{nm}' not found under skills/", file=sys.stderr)
    return out


# ── memory stores & knowledge (the Agent→Project→Session→Context model) ────────
# A memory store / knowledge doc is attached at SESSION creation in `resources[]`
# (NOT on the agent). build.py reads the declarative catalogs in cma.yaml and turns
# every memory/knowledge reference into a resources[] entry. Real ids only exist
# after the platform creates them at deploy time, so the dry-run emits scope-aware
# placeholders the platform substitutes per (agent, project, session):
#
#   scope=agent   → ${MEMSTORE_<KEY>}                  (one store, shared by all projects)
#   scope=project → ${MEMSTORE_<KEY>__<PROJECT>}       (one store PER project)
#   scope=session → ${MEMSTORE_<KEY>__SESSION}         (a fresh store PER session)
#
# Knowledge mirrors this with ${FILE_<KEY>...} / repo placeholders.
def _slug(s: str) -> str:
    return re.sub(r"[^A-Z0-9]", "_", str(s).upper())


def _scoped_placeholder(prefix: str, key: str, scope: str, project: str | None) -> str:
    base = f"{prefix}_{_slug(key)}"
    if scope == "project":
        base += "__" + _slug(project or "PROJECT")
    elif scope == "session":
        base += "__SESSION"
    return "${" + base + "}"


def resolve_memory(refs, catalog: dict, project: str | None = None) -> list:
    """memory refs (str key, or {store, access?, instructions?}) → CMA session
    resources[] entries (type=memory_store), scope-aware. The catalog supplies
    scope/access/description/instructions per store."""
    out = []
    for ref in refs or []:
        if isinstance(ref, str):
            ref = {"store": ref}
        key = ref["store"]
        spec = (catalog or {}).get(key, {})
        scope = spec.get("scope", "project")
        entry = {
            "type": "memory_store",
            "memory_store_id": _scoped_placeholder("MEMSTORE", key, scope, project),
            "access": ref.get("access", spec.get("access", "read_write")),
        }
        instr = ref.get("instructions", spec.get("instructions"))
        if instr:
            entry["instructions"] = instr
        out.append(entry)
    return out


def resolve_knowledge(refs, catalog: dict, project: str | None = None) -> list:
    """knowledge refs (str key) → CMA session resources[] entries. `file` knowledge
    becomes {type: file, file_id, mount_path}; `github_repository` becomes
    {type: github_repository, ...}. Ids are scope-aware placeholders."""
    out = []
    for ref in refs or []:
        key = ref if isinstance(ref, str) else ref.get("knowledge", ref.get("store"))
        spec = (catalog or {}).get(key, {})
        scope = spec.get("scope", "project")
        ktype = spec.get("type", "file")
        if ktype == "github_repository":
            entry = {
                "type": "github_repository",
                "repository": spec.get("repo", "your-org/your-repo"),
            }
            if spec.get("mount"):
                entry["mount_path"] = spec["mount"]
        else:  # file
            entry = {
                "type": "file",
                "file_id": _scoped_placeholder("FILE", key, scope, project),
            }
            if spec.get("mount"):
                entry["mount_path"] = spec["mount"]
        if spec.get("access"):
            entry["access"] = spec["access"]
        out.append(entry)
    return out


def build_leaf(leaf: dict, model: str, catalog: dict | None = None) -> dict:
    """One depth-1 subagent JSON from a cma.yaml leaf entry."""
    role = leaf.get("role", "critic")
    name = leaf["as"]
    # prompt: from expert md body, or inline prompt for synthetic leaves (packager)
    if "expert" in leaf:
        fm, body = parse_frontmatter((REPO / leaf["expert"]).read_text())
        prompt = body.strip()
        skills = resolve_skills(fm.get("skills"))
    else:
        prompt = (leaf.get("prompt") or "").strip()
        skills = []
    node = {
        "name": name,
        "model": model,
        "system": {"text": prompt},
        "tools": tools_to_toolset(ROLE_TOOLS[role]),
        "mcp_servers": [],
        "skills": skills,
        "callable_agents": [],          # depth-1: leaves never nest (CMA one-level rule)
    }
    if role == "reader" and leaf.get("schema"):
        node["output_schema"] = json.loads((REPO / leaf["schema"]).read_text())
    return node


def build_workflow(name: str, wf: dict, model: str, headless: str,
                   catalog: dict | None = None, know_catalog: dict | None = None,
                   agent_cfg: dict | None = None, project: dict | None = None,
                   project_key: str | None = None) -> dict:
    """One orchestrator + its leaves → the CMA agent payload, plus a `session`
    stanza (resources[]) for ONE (project, workflow) pair. The session aggregates
    memory/knowledge from three scopes in precedence order:
        agent  (agent.memory / agent.knowledge)        — every project sees it
        project(projects.<k>.memory / .knowledge)      — only this project
        session(workflow.session_memory, leaf.memory)  — this run only
    Returns {"agent": <payload>, "session": <session params>}."""
    agent_cfg = agent_cfg or {}
    project = project or {}
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
        "callable_agents": [build_leaf(l, model, catalog) for l in wf.get("leaves", [])],
    }

    # ── aggregate memory across scopes (agent → project → session) ──
    mem_refs = []
    mem_refs += list(agent_cfg.get("memory") or [])          # agent scope
    mem_refs += list(project.get("memory") or [])            # project scope
    mem_refs += list(wf.get("session_memory") or [])         # session/workflow scope
    for leaf in wf.get("leaves", []):                        # per-role private memory
        for m in (leaf.get("memory") or []):
            m = {"store": m} if isinstance(m, str) else dict(m)
            m.setdefault("instructions",
                         f"Memory for the '{leaf.get('as','?')}' role. "
                         f"{(catalog or {}).get(m['store'], {}).get('description','')}".strip())
            mem_refs.append(m)
    # de-dup by (store, access)
    seen, mem_dd = set(), []
    for r in mem_refs:
        r = {"store": r} if isinstance(r, str) else r
        k = (r["store"], r.get("access"))
        if k not in seen:
            seen.add(k); mem_dd.append(r)

    # ── aggregate knowledge across scopes (agent → project) ──
    know_refs = list(agent_cfg.get("knowledge") or []) + list(project.get("knowledge") or [])
    know_dd = list(dict.fromkeys(know_refs))   # de-dup, keep order

    resources = (resolve_memory(mem_dd, catalog, project_key)
                 + resolve_knowledge(know_dd, know_catalog, project_key))

    out = {"agent": orch}
    if resources:
        out["session"] = {"agent": "${AGENT_ID}", "environment_id": "${ENVIRONMENT_ID}",
                          "resources": resources}
    return out


def main(argv):
    do_post = "--post" in argv
    model_override = None
    if "--model" in argv:
        model_override = argv[argv.index("--model") + 1]
    targets = [a for a in argv[1:] if not a.startswith("--") and a != model_override]

    manifest = _load_yaml(MANIFEST.read_text())
    model = model_override or _expand_env(str(manifest.get("model", "sonnet")))
    headless = manifest.get("headless_append", "")
    catalog = manifest.get("memory_stores", {})
    know_catalog = manifest.get("knowledge", {})
    agent_cfg = manifest.get("agent", {})
    all_workflows = manifest.get("workflows", {})

    # Projects model: each project declares which workflows it can run. If no
    # `projects:` block exists, synthesize a single default project running every
    # workflow (backward compatible with the pre-projects manifest).
    projects = manifest.get("projects")
    if not projects:
        projects = {"default": {"workflows": list(all_workflows.keys())}}

    for pkey, project in projects.items():
        pwf = project.get("workflows", list(all_workflows.keys()))
        if targets:
            pwf = [w for w in pwf if w in targets]
        if not pwf:
            continue
        print(f"\n########## PROJECT: {pkey}"
              f"{'  (' + project.get('display_name','') + ')' if project.get('display_name') else ''} ##########")
        for name in pwf:
            wf = all_workflows.get(name)
            if wf is None:
                print(f"  ! project '{pkey}' references unknown workflow '{name}'", file=sys.stderr); continue
            built = build_workflow(name, wf, model, headless, catalog, know_catalog,
                                   agent_cfg, project, pkey)
            payload = built["agent"]
            n_leaves = len(payload["callable_agents"])
            writers = [l["name"] for l in payload["callable_agents"]
                       if any(c["name"] in ("write", "edit") for ts in l["tools"] for c in ts["configs"])]
            res = built.get("session", {}).get("resources", [])
            ids = [r.get("memory_store_id") or r.get("file_id") or r.get("repository") for r in res]
            print(f"\n===== workflow: {name}  (project={pkey}, model={model}, leaves={n_leaves}, "
                  f"writers={writers}{', resources=' + str(ids) if ids else ''}) =====")
            print("# agent  (POST /v1/agents) — created once per agent, reused across projects/sessions")
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            if "session" in built:
                print("# session  (POST /v1/sessions) — one session = one task; attaches this "
                      "project's memory+knowledge at creation. Context lives only here.")
                print(json.dumps(built["session"], indent=2, ensure_ascii=False))
            if do_post:
                print(f"  [--post] would upload skills + POST /v1/agents for '{name}' "
                      f"(wire to anthropic SDK / deploy here)", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
