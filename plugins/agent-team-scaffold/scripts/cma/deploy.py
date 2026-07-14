#!/usr/bin/env python3
"""deploy.py — the platform runtime that *fulfils* what cma.yaml declares.

build.py DECLARES (prints agent + session payloads with scope placeholders).
deploy.py FULFILS them against the Claude Managed Agents API:

  1. ensure the AGENT exists           → POST /v1/agents     (created once, reused)
  2. ensure each MEMORY STORE exists   → POST /v1/memory_stores  (lazily, per scope)
       scope=agent   → one store, shared by every project/session
       scope=project → one store PER project
       scope=session → a fresh store PER session
  3. ensure each KNOWLEDGE doc exists  → POST /v1/files (upload) or repo passthrough
  4. open a SESSION in a project       → POST /v1/sessions   (resources resolved)
  5. start it                          → POST /v1/sessions/:id/events (user.message)

The (scope, key, project?, session?) → real-id map is persisted in
`scripts/cma/.deploy-state.json` (gitignored) so agent/project stores are reused
and only session stores are fresh each run.

Dependency-light: stdlib only (urllib). Default is DRY-RUN — it prints every API
call it would make and fabricates deterministic fake ids, so you can run it with no
credentials. Pass --apply to make real calls (needs the env vars below).

Usage:
  python3 scripts/cma/deploy.py agent                          # ensure the agent (dry-run)
  python3 scripts/cma/deploy.py session default deliver-feature "Build a CSV importer"
  python3 scripts/cma/deploy.py session acme deliver-feature --apply
  python3 scripts/cma/deploy.py status                         # show the id map
  python3 scripts/cma/deploy.py reset                          # forget the id map

Env (only needed with --apply):
  ANTHROPIC_API_KEY            your API key
  ANTHROPIC_ENVIRONMENT_ID     a Managed Agents environment id (cloud sandbox)
  CMA_MODEL                    model tier (default sonnet); coordinator stays opus

Managed Agents is BETA: all calls send `anthropic-beta: managed-agents-2026-04-01`.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

CMA_DIR = Path(__file__).resolve().parent
REPO = CMA_DIR.parents[1]
STATE_FILE = CMA_DIR / ".deploy-state.json"

sys.path.insert(0, str(CMA_DIR))
import build  # reuse the SAME readers/derivation as the declarative side

API_BASE = "https://api.anthropic.com"
BETA = "managed-agents-2026-04-01"
ANTHROPIC_VERSION = "2023-06-01"


# ── state (the (scope,key,project,session) → real-id map) ─────────────────────
def load_state() -> dict:
    if STATE_FILE.is_file():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            pass
    return {"agent_id": None, "agent_version": None, "stores": {}, "files": {}}


def save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, indent=2, ensure_ascii=False))


# ── transport (dry-run records intent; http makes real calls) ─────────────────
class Transport:
    def __init__(self, apply: bool):
        self.apply = apply
        self._n = 0

    def _fake_id(self, prefix: str) -> str:
        self._n += 1
        return f"{prefix}_DRYRUN{self._n:03d}"

    def post(self, path: str, body: dict, id_prefix: str = "obj") -> dict:
        url = API_BASE + path
        if not self.apply:
            print(f"  → POST {path}")
            preview = json.dumps(body, ensure_ascii=False)
            print(f"      body: {preview[:200]}{'…' if len(preview) > 200 else ''}")
            return {"id": self._fake_id(id_prefix)}
        return self._http("POST", url, body)

    def upload_file(self, file_path: Path) -> dict:
        if not self.apply:
            print(f"  → POST /v1/files  (multipart upload {file_path.name})")
            return {"id": self._fake_id("file")}
        return self._http_multipart(API_BASE + "/v1/files", file_path)

    def _headers(self) -> dict:
        key = os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise SystemExit("ANTHROPIC_API_KEY required with --apply")
        return {
            "x-api-key": key,
            "anthropic-version": ANTHROPIC_VERSION,
            "anthropic-beta": BETA,
            "content-type": "application/json",
        }

    def _http(self, method: str, url: str, body: dict) -> dict:
        data = json.dumps(body).encode()
        req = urllib.request.Request(url, data=data, method=method, headers=self._headers())
        try:
            with urllib.request.urlopen(req) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            raise SystemExit(f"API {method} {url} failed: {e.code} {e.read().decode()[:500]}")

    def _http_multipart(self, url: str, file_path: Path) -> dict:
        boundary = "----cmadeploy"
        body = bytearray()
        body += f"--{boundary}\r\n".encode()
        body += (f'Content-Disposition: form-data; name="file"; filename="{file_path.name}"\r\n'
                 f"Content-Type: application/octet-stream\r\n\r\n").encode()
        body += file_path.read_bytes()
        body += f"\r\n--{boundary}--\r\n".encode()
        headers = self._headers()
        headers["content-type"] = f"multipart/form-data; boundary={boundary}"
        req = urllib.request.Request(url, data=bytes(body), method="POST", headers=headers)
        try:
            with urllib.request.urlopen(req) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            raise SystemExit(f"file upload failed: {e.code} {e.read().decode()[:500]}")


# ── manifest helpers ──────────────────────────────────────────────────────────
def manifest() -> dict:
    return build._load_yaml((CMA_DIR / "cma.yaml").read_text())


def model_of(m: dict) -> str:
    return os.environ.get("CMA_MODEL") or build._expand_env(str(m.get("model", "sonnet")))


# ── 1. ensure the agent ────────────────────────────────────────────────────────
def ensure_agent(m: dict, tx: Transport, state: dict) -> str:
    if state.get("agent_id"):
        print(f"agent: reuse {state['agent_id']}")
        return state["agent_id"]
    model = model_of(m)
    headless = m.get("headless_append", "")
    cat, know, acfg = m.get("memory_stores", {}), m.get("knowledge", {}), m.get("agent", {})
    # build the agent payload from the first workflow (the orchestrator carries the team).
    wfname, wf = next(iter((m.get("workflows") or {}).items()))
    built = build.build_workflow(wfname, wf, model, headless, cat, know, acfg, {}, None)
    payload = built["agent"]
    payload["name"] = acfg.get("name", payload["name"])
    if acfg.get("display_name"):
        payload["display_name"] = acfg["display_name"]
    print(f"agent: create '{payload['name']}' (model={model}, leaves={len(payload['callable_agents'])})")
    print("  note: skills are referenced by skill_ref; upload them to your workspace before --apply "
          "(see docs/platform-design.zh.md section 8).")
    res = tx.post("/v1/agents", payload, "agnt")
    state["agent_id"] = res["id"]
    state["agent_version"] = res.get("version", 1)
    save_state(state)
    print(f"  → agent_id = {res['id']}")
    return res["id"]


# ── 2/3. ensure stores + knowledge for a scope key ─────────────────────────────
def _scope_state_key(kind: str, key: str, scope: str, project: str | None, session: str | None) -> str:
    """The cache key in state — agent stores shared, project stores per-project,
    session stores per-session (so they are NOT reused)."""
    parts = [kind, key]
    if scope == "project":
        parts.append(project or "default")
    elif scope == "session":
        parts.append(session or "adhoc")
    return ":".join(parts)


def ensure_store(key: str, catalog: dict, tx: Transport, state: dict,
                 project: str | None, session: str | None) -> str:
    spec = catalog.get(key, {})
    scope = spec.get("scope", "project")
    sk = _scope_state_key("memstore", key, scope, project, session)
    # session-scoped stores are always fresh; others are cached/reused
    if scope != "session" and sk in state["stores"]:
        return state["stores"][sk]
    name = f"{key}" + (f" · {project}" if scope == "project" and project else "")
    body = {"name": name, "description": spec.get("description", key)}
    res = tx.post("/v1/memory_stores", body, "memstore")
    # seed: upload the typed seed file (memory/seeds/*.md) as the store's first memory
    seed = spec.get("seed")
    if seed:
        seed_path = REPO / seed
        if seed_path.is_file():
            tx.post(f"/v1/memory_stores/{res['id']}/memories",
                    {"path": f"/{seed_path.name}", "content": seed_path.read_text()},
                    "memory")
        else:
            print(f"  ! seed file not found, store created unseeded: {seed}", file=sys.stderr)
    if scope != "session":
        state["stores"][sk] = res["id"]
        save_state(state)
    return res["id"]


def ensure_knowledge_file(key: str, know: dict, tx: Transport, state: dict,
                          project: str | None) -> str:
    spec = know.get(key, {})
    scope = spec.get("scope", "project")
    sk = _scope_state_key("file", key, scope, project, None)
    if sk in state["files"]:
        return state["files"][sk]
    src = REPO / spec.get("path", "")
    if not src.is_file():
        print(f"  ! knowledge file missing: {spec.get('path')} (key={key}) — skipping", file=sys.stderr)
        return ""
    res = tx.upload_file(src)
    state["files"][sk] = res["id"]
    save_state(state)
    return res["id"]


# ── 4/5. open a session in a project and start it ──────────────────────────────
def resolve_resources(resources: list, m: dict, tx: Transport, state: dict,
                      project: str, session_tag: str) -> list:
    """Replace every scope placeholder in a session resources[] with a real id."""
    cat, know = m.get("memory_stores", {}), m.get("knowledge", {})
    # reverse-map placeholders back to catalog keys by matching build.py's scheme
    out = []
    for r in resources:
        r = dict(r)
        if r["type"] == "memory_store":
            key = _placeholder_to_key(r["memory_store_id"], cat, "MEMSTORE")
            r["memory_store_id"] = ensure_store(key, cat, tx, state, project, session_tag)
        elif r["type"] == "file":
            key = _placeholder_to_key(r["file_id"], know, "FILE")
            fid = ensure_knowledge_file(key, know, tx, state, project)
            if not fid:
                continue
            r["file_id"] = fid
        # github_repository passes through unchanged (repo string is real already)
        out.append(r)
    return out


def _placeholder_to_key(placeholder: str, catalog: dict, prefix: str) -> str:
    """${MEMSTORE_PROJECT_CONTEXT__ACME} → 'project-context' by matching catalog keys."""
    inner = placeholder.strip("${}")
    if inner.startswith(prefix + "_"):
        inner = inner[len(prefix) + 1:]
    inner = inner.split("__")[0]              # drop the __PROJECT / __SESSION suffix
    for key in catalog:
        if build._slug(key) == inner:
            return key
    return inner.lower().replace("_", "-")     # best-effort fallback


def open_session(project_key: str, workflow: str, message: str | None,
                 tx: Transport, state: dict):
    m = manifest()
    projects = m.get("projects") or {"default": {"workflows": list((m.get("workflows") or {}).keys())}}
    project = projects.get(project_key)
    if project is None:
        raise SystemExit(f"unknown project '{project_key}' (have: {', '.join(projects)})")
    if workflow not in (project.get("workflows") or []):
        raise SystemExit(f"project '{project_key}' does not run workflow '{workflow}'")

    agent_id = ensure_agent(m, tx, state)
    model = model_of(m)
    built = build.build_workflow(workflow, m["workflows"][workflow], model,
                                 m.get("headless_append", ""), m.get("memory_stores", {}),
                                 m.get("knowledge", {}), m.get("agent", {}), project, project_key)
    sess = built.get("session", {"resources": []})

    env_id = os.environ.get("ANTHROPIC_ENVIRONMENT_ID", "${ENVIRONMENT_ID}")
    if tx.apply and env_id == "${ENVIRONMENT_ID}":
        raise SystemExit("ANTHROPIC_ENVIRONMENT_ID required with --apply")

    session_tag = f"{project_key}-{workflow}"
    print(f"\nsession: project={project_key} workflow={workflow}")
    resources = resolve_resources(sess.get("resources", []), m, tx, state, project_key, session_tag)
    body = {"agent": agent_id, "environment_id": env_id, "resources": resources}
    res = tx.post("/v1/sessions", body, "sesn")
    session_id = res["id"]
    print(f"  → session_id = {session_id}  ({len(resources)} resources attached)")

    if message:
        ev = {"events": [{"type": "user.message", "content": [{"type": "text", "text": message}]}]}
        tx.post(f"/v1/sessions/{session_id}/events", ev, "evt")
        print(f"  → started with: {message!r}")
    else:
        print("  (no message given — session provisioned but not started; "
              "send a user.message to begin)")
    return session_id


# ── status / reset ─────────────────────────────────────────────────────────────
def cmd_status(state: dict):
    print(f"agent_id   : {state.get('agent_id')}")
    print(f"agent_ver  : {state.get('agent_version')}")
    print("memory stores (scope:key[:project|:session] → id):")
    for k, v in state.get("stores", {}).items():
        print(f"  {k}  →  {v}")
    print("knowledge files (file:key[:project] → id):")
    for k, v in state.get("files", {}).items():
        print(f"  {k}  →  {v}")
    if not state.get("stores") and not state.get("files") and not state.get("agent_id"):
        print("  (empty — nothing deployed yet)")


def main(argv):
    p = argparse.ArgumentParser(description="Managed Agents platform runtime for agent-team-scaffold")
    p.add_argument("command", choices=["agent", "session", "status", "reset"])
    p.add_argument("args", nargs="*", help="for `session`: <project> <workflow> [message]")
    p.add_argument("--apply", action="store_true", help="make real API calls (default: dry-run)")
    ns = p.parse_args(argv[1:])

    state = load_state()
    tx = Transport(apply=ns.apply)
    mode = "APPLY" if ns.apply else "DRY-RUN"
    print(f"[{mode}] state: {STATE_FILE.relative_to(REPO)}")

    if ns.command == "status":
        cmd_status(state); return
    if ns.command == "reset":
        if STATE_FILE.exists():
            STATE_FILE.unlink()
        print("state reset."); return
    if ns.command == "agent":
        ensure_agent(manifest(), tx, state); return
    if ns.command == "session":
        if len(ns.args) < 2:
            raise SystemExit("usage: deploy.py session <project> <workflow> [message] [--apply]")
        project_key, workflow = ns.args[0], ns.args[1]
        message = " ".join(ns.args[2:]) if len(ns.args) > 2 else None
        open_session(project_key, workflow, message, tx, state)


if __name__ == "__main__":
    main(sys.argv)
