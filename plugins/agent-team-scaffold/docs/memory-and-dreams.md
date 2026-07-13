# Memory, Knowledge, Dreams & Per-Agent Context

How the agent-team-scaffold gives its roles **persistent memory**, **knowledge /
RAG documents**, **isolated context**, and **self-curating memory via dreams** —
using Claude Managed Agents.

> Source: [Managed Agents — overview](https://platform.claude.com/docs/en/managed-agents/overview),
> [memory](https://platform.claude.com/docs/en/managed-agents/memory),
> [files](https://platform.claude.com/docs/en/managed-agents/files),
> [tools](https://platform.claude.com/docs/en/managed-agents/tools),
> [dreams](https://platform.claude.com/docs/en/managed-agents/dreams),
> [multiagent](https://platform.claude.com/docs/en/managed-agents/multi-agent).
> All requests need the `managed-agents-2026-04-01` beta header; dreams also need
> `dreaming-2026-04-21`. These are **beta / research-preview** features.

---

## The three facts that shape everything

1. **Memory lives in *memory stores*, attached at the *session*, not on the agent.**
   A memory store (`memstore_…`) is a workspace-scoped collection of markdown,
   mounted into the session sandbox under `/mnt/memory/`. You attach it in the
   session's `resources[]` at creation time (you **cannot** add/remove one from a
   running session). Each agent's *definition* carries model / system / tools /
   MCP — **never** a memory store.

2. **Memory "scopes" are a pattern, not a field.** There is no `scope: global`
   knob. A scope is *which store you attach, with what `access`, to which
   sessions*:
   - **Global** = one `read_only` store attached to every session (house standards).
   - **Project** = one `read_write` store per project, attached to that project's sessions.
   - **Per-agent** = a store only that agent's session attaches (its private memory).

3. **Isolated context comes from multiagent threads.** In a `multiagent`
   coordinator session, *"each agent runs in its own session thread, a
   context-isolated event stream with its own conversation history… Tools, MCP
   servers, and context are not shared."* That is how a sub-agent gets its **own
   independent context**.

How this scaffold encodes it: `scripts/cma/cma.yaml` has a `memory_stores:`
catalog and lets each workflow declare `session_memory:` (global+project) and each
leaf declare `memory:` (per-agent). `build.py` turns those into the session
`resources[]` stanza. Real ids are created at deploy time; the dry-run prints
`${MEMSTORE_<KEY>}` placeholders.

---

## Memory stores: create, seed, attach

### 1. Create a store

```bash
store=$(curl -s https://api.anthropic.com/v1/memory_stores \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{"name": "Project Context", "description": "This project'\''s decisions, glossary, prior outcomes."}')
store_id=$(jq -r '.id' <<< "$store")   # memstore_01Hx...
```

### 2. Seed it (optional)

```bash
curl -s "https://api.anthropic.com/v1/memory_stores/$store_id/memories" \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" -H "content-type: application/json" \
  -d '{"path": "/decisions/0001-loop.md", "content": "We use the Planner→Generator→Evaluator loop. Evaluator owns PASS/FAIL."}'
```

> Limits: each memory ≤ 100 kB (~25k tokens); ≤ 2,000 memories per store; ≤ 8
> stores per session. Prefer many small focused files over a few large ones.

### 3. Attach at session creation (`resources[]`)

This is the exact shape `build.py` emits. `access` defaults to `read_write`;
use `read_only` for shared/reference stores. `instructions` (≤ 4,096 chars) is
shown to the agent next to the mount.

```json
{
  "agent": "$AGENT_ID",
  "environment_id": "$ENVIRONMENT_ID",
  "resources": [
    { "type": "memory_store", "memory_store_id": "$store_id",
      "access": "read_write",
      "instructions": "Project memory. Check before scoping; record durable decisions." }
  ]
}
```

The agent reads/writes the mount with its ordinary file tools (the **agent
toolset must be enabled** on the agent). Every write creates an immutable
**memory version** (`memver_…`) — a full audit trail with point-in-time recovery.

> **Injection warning (from the docs).** `read_write` + untrusted input = a
> prompt-injection can poison memory that later sessions trust. Attach reference
> material `read_only`. In this scaffold the schema-bound `planner` (reader role,
> no write tools) and the read-only stores are the mitigations.

---

## The three memory scopes — as wired in this scaffold

`cma.yaml` declares the catalog:

```yaml
memory_stores:
  team-standards:        # GLOBAL  — shared, authoritative, read-only
    description: "Org-wide conventions and definitions of done."
    access: read_only
    instructions: "Authoritative house standards. Read before planning/judging; never write here."
  project-context:       # PROJECT — per-project, read-write, outlives any session
    description: "This project's decisions, glossary, prior sprint outcomes, open risks."
    access: read_write
    instructions: "The project's running memory. Record durable decisions; check before scoping."
  evaluator-calibration: # PER-AGENT — private to the evaluator role
    description: "The evaluator's calibration notes: recurring failure modes, leniency-drift catches."
    access: read_write
    instructions: "Your private calibration memory. Append patterns you miss; consult before each verdict."
```

and the workflow references them:

```yaml
deliver-feature:
  session_memory:                 # whole-session → GLOBAL + PROJECT
    - team-standards              #   read_only
    - project-context             #   read_write
  leaves:
    - { as: evaluator, expert: …/evaluator.md, role: critic,
        memory: [evaluator-calibration] }   # PER-AGENT
```

| Scope | Store | access | Attached to | Lifecycle |
|---|---|---|---|---|
| **Global** | `team-standards` | `read_only` | every session, every project | outlives all; curated by humans |
| **Project** | `project-context` | `read_write` | this project's sessions | outlives any one session |
| **Per-agent** | `evaluator-calibration` | `read_write` | only the evaluator's session/thread | private to that role |

Run `python3 scripts/cma/build.py deliver-feature` to see the resolved session
`resources[]` for all three.

### A note on "per-agent" inside one multiagent session

All agents in a single multiagent session **share one sandbox and filesystem**,
so a memory store mounted there is physically reachable by any of them. There are
two honest ways to give a sub-agent *its own* memory:

- **Naming + discipline (lightweight).** Attach the store and name its owner in
  `instructions` ("the evaluator's private calibration memory"). This is what the
  scaffold does by default — simple, but not enforced isolation.
- **Own session (true isolation).** Run that agent as its **own session** with
  **only** its store attached. Because memory attaches per session, a store you
  attach to the evaluator's session and to no other is genuinely private. Combine
  with per-agent context isolation (next section).

---

## Per-agent isolated context (multiagent)

To give a sub-agent its **own context window**, make the team a `multiagent`
coordinator. Each rostered agent then runs in its own context-isolated thread
with its own model, tools, and MCP servers.

```bash
# 1) Define each sub-agent with ITS OWN model / tools / mcp_servers (own context).
evaluator_id=$(curl -s …/v1/agents -d '{
  "name": "evaluator",
  "model": "claude-opus-4-8",
  "tools": [{"type": "agent_toolset_20260401"}]
}' | jq -r .id)

# 2) Define the coordinator and declare the roster it may delegate to.
coordinator_id=$(curl -s …/v1/agents -d "{
  \"name\": \"coordinator\",
  \"model\": \"claude-opus-4-8\",
  \"tools\": [{\"type\": \"agent_toolset_20260401\"}],
  \"multiagent\": {
    \"type\": \"coordinator\",
    \"agents\": [
      {\"type\": \"agent\", \"id\": \"$planner_id\"},
      {\"type\": \"agent\", \"id\": \"$generator_id\"},
      {\"type\": \"agent\", \"id\": \"$evaluator_id\"}
    ]
  }
}" | jq -r .id)
```

Key facts (verbatim from the docs):
- *"each agent runs in its own session thread… with its own conversation
  history. Tools, MCP servers, and context are not shared."*
- *"Each agent uses its own configuration (model, system prompt, tools, MCP
  servers, and skills) as defined when that agent was created."*
- The coordinator delegates **one level only** (depth > 1 is ignored); ≤ 20
  agents in the roster; ≤ 25 concurrent threads. `{"type": "self"}` lets the
  coordinator spawn copies of itself.
- MCP servers are **agent-scoped** (declare only what each agent needs); vault
  credentials are **session-scoped** (`vault_ids` apply to every thread).

This is the headless mirror of the scaffold's local one-level delegation
(`coordinator → planner → design-evaluator → generator → evaluator → packager`).
The coordinator is the natural `multiagent.coordinator`; each specialist is a
rostered agent with its own context.

> **Combining the two for a private-memory evaluator:** give the evaluator its
> own agent definition (own context) **and** run a per-agent session that
> attaches only `evaluator-calibration`. The coordinator delegates to it; its
> reasoning, tools, and memory are all isolated from the rest of the team.

---

## Dreams: let memory curate itself

Agents write to memory incrementally, so a store accumulates duplicates,
contradictions, and stale entries. A **dream** is an async job that reads one
input store + 1–100 past sessions and produces a **new, reorganized output
store** — duplicates merged, stale entries replaced, new insights surfaced. **The
input is never modified**, so you review the output and keep or discard it.

```bash
dream=$(curl -s https://api.anthropic.com/v1/dreams \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01,dreaming-2026-04-21" \
  -H "content-type: application/json" \
  -d '{
    "inputs": [
      { "type": "memory_store", "memory_store_id": "'"$store_id"'" },
      { "type": "sessions", "session_ids": ["'"$session_a"'", "'"$session_b"'"] }
    ],
    "model": "claude-opus-4-8",
    "instructions": "Focus on evaluator calibration patterns; drop one-off debugging notes."
  }')
dream_id=$(jq -r '.id' <<< "$dream")   # drm_01...
```

- Poll by id until `status` is `completed` (`pending → running → completed |
  failed | canceled`); typically minutes to tens of minutes.
- On `completed`, the new store id is in `outputs[]`:
  ```bash
  output_store_id=$(jq -r 'first(.outputs[]|select(.type=="memory_store")).memory_store_id' <<< "$dream")
  ```
  Attach it to future sessions in place of the input, or delete/archive it.
- `instructions` (≤ 4,096 chars) steer high-level synthesis (focus areas, what to
  preserve), **not** line edits — for targeted fixes use the Memory Stores API.
- Limits: ≤ 100 sessions per dream; models `claude-opus-4-8`, `claude-opus-4-7`,
  `claude-sonnet-4-6`. Billed at standard token rates.

### Where dreams fit this scaffold

The natural target is the **`evaluator-calibration`** and **`project-context`**
stores. After a batch of `deliver-feature` sessions, dream over the calibration
store + those session ids to consolidate "patterns the evaluator keeps missing"
into a clean store — then attach the output to future evaluator sessions. This is
the **coordinator's** kind of job (it owns evaluator calibration), run on a
schedule (e.g. end of sprint), with a human reviewing the output before adoption.

---

## Knowledge & RAG: it's the filesystem, not a vector index

The single most important thing to understand: **Managed Agents has no built-in
vector store, embedding index, or `rag_search`/`file_search` retrieval tool.**
Knowledge is **documents mounted into the sandbox**, and "retrieval" is the agent
using its ordinary file tools — **`grep`, `glob`, `read`** — over those documents
(plus `web_search` / `web_fetch` for the live web). The full built-in toolset is:

| Tool | Name | Use for knowledge |
|---|---|---|
| Read | `read` | open a mounted document |
| Glob | `glob` | find documents by path/pattern |
| Grep | `grep` | regex search *across* mounted documents (this is your "retrieval") |
| Web search | `web_search` | search the live web |
| Web fetch | `web_fetch` | pull a URL's content |
| Bash | `bash` | unzip archives, run a local index/`ripgrep`, parse CSV/JSON, etc. |

So a "RAG corpus" in Managed Agents is **a directory of files (and/or a repo) the
agent searches with grep/glob**. If you need true semantic/vector retrieval, you
expose it as an **MCP server** (your own vector DB behind the [MCP
connector](https://platform.claude.com/docs/en/managed-agents/mcp-connector)) or a
**custom tool** — it is not a native primitive.

### Three ways knowledge reaches the agent

| Source | `resources[]` type | Mount | Mutable on a running session? | Best for |
|---|---|---|---|---|
| **Uploaded files** (Files API) | `file` | `mount_path` you choose (read-only copy) | **Yes** — `resources.add` / `resources.delete` | docs, datasets, PDFs/CSVs, a knowledge pack |
| **GitHub repository** | `github_repository` † | repo working tree in the sandbox | Yes | a codebase / docs repo as knowledge |
| **Memory store** | `memory_store` | `/mnt/memory/` | **No** — attach at creation only | durable, agent-*writable* knowledge that persists across sessions |

† The repository resource type is confirmed in the SDK resource union
(`resources.list` returns file / github\_repository / memory\_store entries), but
its exact field schema is not on a fetchable public docs page as of this writing —
treat the repo example below as illustrative and verify field names against the
current SDK before deploying.

### Attach documents as knowledge (files)

Upload through the Files API, then mount in `resources[]`. Mounted files are
**read-only copies**, up to **100 files per session**, and the copies don't count
against storage limits.

```bash
# 1) upload
file_id=$(curl -sS https://api.anthropic.com/v1/files \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -F file=@handbook.md | jq -r '.id')

# 2) mount as knowledge when creating the session
curl -s https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" -H "content-type: application/json" \
  --data @- <<EOF
{
  "agent": "$AGENT_ID",
  "environment_id": "$ENVIRONMENT_ID",
  "resources": [
    { "type": "file", "file_id": "$file_id", "mount_path": "/workspace/knowledge/handbook.md" }
  ]
}
EOF
```

The agent then "retrieves" by searching the mount, e.g.
`grep -ri "refund policy" /workspace/knowledge/` then `read` the hit. Add or remove
knowledge on a **running** session:

```bash
# add a doc mid-session
curl -s "https://api.anthropic.com/v1/sessions/$SESSION_ID/resources" \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" -H "content-type: application/json" \
  -d "{\"type\": \"file\", \"file_id\": \"$file_id\"}"   # → returns sesrsc_... (use to delete)
```

### Knowledge vs. memory — when to use which

| | **Knowledge** (files / repo) | **Memory** (memory store) |
|---|---|---|
| Direction | read-only reference *in* | agent *writes* what it learns |
| Lifetime | the session (re-mount each time) | persists across sessions |
| Search | grep/glob/read over the mount | grep/glob/read over `/mnt/memory/` |
| Mutable mid-session | yes (files) | no (creation-only) |
| Curated by | you upload it | the agent writes it; **dreams** clean it |
| Use it for | the corpus to consult (handbook, codebase, datasets) | preferences, decisions, calibration the agent accrues |

They compose: mount the **knowledge corpus** read-only, and give the agent a
**memory store** to write down what it concluded from it. A **dream** later
consolidates the memory; the knowledge corpus is just re-mounted, never dreamed.

### How this scaffold uses knowledge

- A **`team-standards`** global store is durable, agent-readable reference
  (memory, `read_only`) — the always-on house rules.
- A **knowledge corpus** (uploaded files or a docs repo) is what the **planner**
  and **generator** consult for a specific deliverable: mount it `read_only` under
  `/workspace/knowledge/`, and they `grep`/`read` it instead of guessing.
- For semantic retrieval over a large corpus, wire your vector DB as an **MCP
  server** in `.mcp.json` and authorize only the roles that need it (per-agent
  `mcpServers`), exactly as the scaffold already does for the filesystem MCP.

> The CMA layer (`scripts/cma/`) models **memory** stores declaratively today.
> Knowledge files/repos are attached at deploy time in the session `resources[]`
> alongside the memory entries `build.py` emits — add `file` / `github_repository`
> entries to that same array. (A future `knowledge:` manifest key could generate
> them; for now they are a documented deploy-time step.)

---

## Mapping to the local plugin

| Managed-Agents concept | Local-plugin analogue in this repo |
|---|---|
| Memory store (`resources[]`) | a markdown dir the agents read/write; `read_only` reference vs `read_write` working memory |
| Global scope | `team-standards` → e.g. `docs/` house standards loaded read-only |
| Project scope | `project-context` → the repo's own running notes (`./out/`, decisions) |
| Per-agent scope | `evaluator-calibration` → a store only the evaluator's session attaches |
| Knowledge / RAG (files + repo, grep/read) | read-only docs the planner/generator consult; a docs dir or the repo itself |
| Vector / semantic retrieval | an MCP server in `.mcp.json` (no native primitive) |
| Multiagent threads | the one-level `Task` delegation (`coordinator → … → packager`) |
| Dream | a scheduled consolidation pass over calibration/project memory, human-reviewed |

The CMA layer (`scripts/cma/`) is the bridge: declare stores in `cma.yaml`,
`build.py` emits the session `resources[]`, and at deploy you create the real
stores and export `MEMSTORE_*` ids.
