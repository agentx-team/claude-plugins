# agent-team-scaffold

A **domain-agnostic scaffold for building an AI agent team** as a Claude Code /
Cowork plugin, built around one validated skeleton: the
**Planner → Generator → Evaluator** loop (Anthropic Engineering,
*Harness Design for Long-Running Apps* + *Building a Multi-Agent Research System*).

It is also a **reference library for the Claude Code plugin spec**: every plugin
primitive — agents, skills, commands, hooks, rules-via-hook, MCP, LSP, output
styles, monitors, PATH binaries, `settings.json`, `userConfig` — appears here as
a runnable minimal example you can copy for your own plugin.

**Local-first** — use it directly in Claude Code or Cowork with no build step —
and the *same* agent assets deploy headless to **Claude Managed Agents (CMA)** via
one small Python compiler. One source, two surfaces. Copy this repo, fill in your
vertical, ship.

```
5 role agents · 1 reference workflow · 3 reference skills · 3 thin commands · 5 hooks · 2 rules
```

## How to use

### 1. Install the plugin

Add the AgentX marketplace (once) and install:

```bash
claude plugin marketplace add agentx-team/claude-plugins
claude plugin install agent-team@agentx-plugins
```

Or, working from a local checkout:

```bash
claude plugin marketplace add /path/to/claude-plugins   # repo root (the marketplace)
claude plugin install agent-team@agentx-plugins
```

On enable, the plugin asks for two **userConfig** values (both have defaults, just
press Enter to accept): `default_model` (the Sonnet-tier roles' model) and
`evaluator_strictness` (`standard` / `strict` / `panel`).

> No credentials, no external services, no Node — the plugin is pure markdown +
> bash + Python stdlib (the CMA build additionally wants `pip install pyyaml`).

### 2. Run the loop

In a session:

```
/agent-team:start a CSV import feature                            # intake → routes into the loop
/agent-team:workflows:deliver-feature CSV import for settings     # run the loop directly
/agent-team:status                                                # read-only loop state
```

### 3. Preview / deploy the CMA surface (optional)

```bash
cma-check                                    # validate manifest + skill refs + no nesting (on PATH while enabled)
python3 scripts/cma/build.py                 # dry-run: print resolved CMA JSON for every workflow
python3 scripts/cma/build.py deliver-feature # one workflow
python3 scripts/cma/build.py --model opus    # override model (also: CMA_MODEL=haiku ...)
cma-deploy session <project> <workflow>      # fulfil against the Managed Agents API (dry-run by default)
```

---

## The core idea: one source produces, a separate agent judges

LLMs grade their own work leniently. The single biggest lever for quality in a
long-running agent team is to **separate the agent that produces from the agent
that judges**, and to tune the judge to be skeptical. That separation is this
scaffold's skeleton:

```
Planner ──spec──▶ Design Evaluator ──APPROVE──▶ Generator ──build──▶ Evaluator ──PASS──▶ Resolver ──▶ ./out/
   ▲                    │ REVISE                                          │ FAIL
   └────────────────────┘                                                ▼
                                                                      Generator (fix & resubmit)
```

| Role | What it does | Verdict |
|---|---|---|
| **Planner** | Decomposes the request into a sprint contract with binary, testable criteria | sprint contract |
| **Design Evaluator** | Adversarially challenges the *plan* before any build | APPROVE / REVISE |
| **Generator** | Implements against the approved contract (never self-certifies) | the deliverable |
| **Evaluator** | Adversarially challenges the *build*; the most important role | PASS / FAIL |
| **Coordinator** | Owns the loop: calibrates evaluators, resolves disputes (Opus) | — |

The Evaluators carry an explicit **anti-leniency mandate** — file the borderline
issue, don't rationalize it away; when in doubt, FAIL. See `docs/coordination-rules.md`.

---

## Directory structure

Everything below is the **standard plugin layout**: auto-discovered directories at
the plugin root, the manifest under `.claude-plugin/`, all hook/monitor paths via
`${CLAUDE_PLUGIN_ROOT}`. There is no `.claude/` directory — a plugin ships its
governance through the plugin surface itself (hooks + rules, below).

```
agent-team-scaffold/
├── .claude-plugin/
│   └── plugin.json               ★ the manifest — identity, explicit agent list, userConfig
├── agents/                       ★ the orchestration logic — md is the single source of truth
│   ├── workflows/                │  end-to-end orchestrators (one per deliverable type)
│   │   └── deliver-feature.md    │    the reference Planner→Generator→Evaluator loop (copy & rename)
│   └── specialists/              │  reusable role agents, grouped by loop role
│       ├── planning/planner.md
│       ├── generation/generator.md
│       ├── evaluation/           │    evaluator.md (build) · design-evaluator.md (plan)
│       └── coordination/coordinator.md
├── skills/                       ★ single source of truth for methods (md), by category
│   ├── authoring/spec-authoring/
│   ├── review/adversarial-review/
│   └── utility/loop-status/
├── commands/                     ★ a FEW upper-level entry points (most work is internal to agents)
│   ├── start.md                  │    requirements intake → routes into the loop
│   ├── status.md                 │    read-only loop status
│   └── workflows/deliver-feature.md   local surface of the reference workflow
├── hooks/
│   ├── hooks.json                event wiring: SessionStart · SubagentStart/Stop · Pre/PostToolUse
│   └── *.sh                      session-start (injects rules/) · log-agent · validate-manifest · validate-push
├── rules/                        always-on guardrails, injected by the SessionStart hook
│   ├── working-surface.md        │    src/ — one writer (the Generator)
│   └── deliverable-package.md    │    out/ — packages staged for human sign-off
├── .mcp.json                     global MCP registration (a filesystem server; per-agent authorized)
├── .lsp.json                     LSP server registration (pyright example)
├── monitors/monitors.json        background monitor — watch-out.sh announces ./out/ sign-off packages
├── output-styles/loop-verdict.md verdict-first, evidence-cited communication style
├── bin/cma-check · cma-deploy    executables added to PATH on enable (validate manifest · deploy)
├── settings.json                 plugin-root settings: agent=coordinator + subagentStatusLine
├── knowledge/house-style.md      agent-scope knowledge example (mounted read-only on CMA)
├── memory/                       the typed-memory taxonomy + seed files
│   ├── README.md                 │    [FACT]/[RULE]/[LEARNED]/[WARNING] — who writes what, where
│   └── seeds/*.md                │    per-store seed examples, uploaded at deploy (cma.yaml `seed:`)
├── scripts/cma/                  the CMA layer — declare (yaml/md) → compile (build/check) → fulfil (deploy)
│   ├── cma.yaml                  │    the ONLY config: agent · memory_stores · knowledge · projects · workflows
│   ├── build.py                  │    DERIVE: projects × workflows → agent + session payloads (no API)
│   ├── check.py                  │    VALIDATE: refs / scopes / workflows (no API; run in CI)
│   ├── deploy.py                 │    FULFIL: POST /v1/agents · memory_stores · files · sessions (dry-run by default)
│   └── schemas/sprint-contract.json   output_schema for the planner (reader) leaf
├── partner-built/                extension point for third-party sub-plugins (empty placeholder)
└── docs/                         platform-design.zh · platform-guide.zh · memory-and-dreams · coordination-rules · agent-roster
```

### About `rules/` — how a plugin ships always-on guidance

Claude Code loads `.claude/rules/*.md` for a **project**, but the plugin spec has
no auto-loaded rules directory. The standard pattern (used here) is:

- keep the rule files in the plugin's own `rules/` directory, with the same
  `paths:` frontmatter a project rule would carry, and
- inject their bodies from the **SessionStart hook** (`hooks/session-start.sh`) —
  SessionStart stdout is added to context at zero model-token cost.

If you fork this scaffold as a *project* (not a plugin), copy `rules/` to
`.claude/rules/` and Claude Code will load them natively, scoped per-path.

### Why this layout
- **`agents/` is the core**: orchestration logic in plain markdown, organized by
  **loop role** rather than domain function. md is the only prompt source — local
  tools load it directly; the CMA layer *derives* its deploy JSON from it.
- **`commands/` is intentionally thin**: a few human entry points (intake, status,
  run-a-workflow). Everything else lives in `skills/` and runs *inside* the loop.
- **CMA stays in `scripts/`**: the project reads as pure agent orchestration;
  headless deployment is one Python file + one tiny manifest.

---

## Plugin surface — the spec, feature by feature

Installed as a Claude Code plugin, the scaffold wires the full plugin feature set.
Everything is a **runnable minimal example** — copy and adapt for your vertical.

| Capability | File | Registered via | What it does |
|---|---|---|---|
| **Manifest** | `.claude-plugin/plugin.json` | — (required) | Identity, keywords, the **explicit agent list** (`agents:` is a replace-default field — listing each `.md` preserves the nested `specialists/` + `workflows/` layout), and the component references below. |
| **Agents** | `agents/**/*.md` | `plugin.json → agents` | Frontmatter: `name`, `description`, `tools`, `model`, `maxTurns`, `skills`, `memory`. Invoked as `agent-team:planner` etc. |
| **Skills** | `skills/<cat>/<name>/SKILL.md` | auto (`skills/` adds to default) | Methods loaded on demand; referenced from agent frontmatter `skills:[...]` by name. |
| **Commands** | `commands/*.md` | `plugin.json → commands` | `/agent-team:start`, `/agent-team:status`, `/agent-team:workflows:deliver-feature`. Frontmatter: `description`, `argument-hint`, `allowed-tools`, `model`. |
| **Hooks** (event-level, whole session) | `hooks/hooks.json` | `plugin.json → hooks` | `SessionStart` loads loop context **and injects `rules/`**; `SubagentStart`/`SubagentStop` append an audit trail; `PreToolUse(Bash)` guards risky pushes; `PostToolUse(Write\|Edit)` re-checks the CMA manifest. All via `${CLAUDE_PLUGIN_ROOT}`. |
| **Rules** | `rules/*.md` | SessionStart hook (see above) | One-writer-per-surface guardrails for `src/` and `out/`. |
| **MCP** (global register, per-agent authorize) | `.mcp.json` | `plugin.json → mcpServers` | A filesystem MCP server over `${CLAUDE_PROJECT_DIR}`. Registered globally; each subagent opts in via its frontmatter `tools:`. |
| **LSP** | `.lsp.json` | `plugin.json → lspServers` | A pyright language server (diagnostics fed back after edits). |
| **Monitor** (background) | `monitors/monitors.json` | `plugin.json → experimental.monitors` | `watch-out.sh` polls `./out/` and notifies when a deliverable is staged for sign-off. *(experimental)* |
| **Output style** | `output-styles/loop-verdict.md` | `plugin.json → outputStyles` | Verdict-first, evidence-cited communication that matches the loop's discipline. |
| **PATH binaries** | `bin/cma-check` · `bin/cma-deploy` | auto (`bin/`) | On the Bash PATH while enabled — validate the CMA manifest / deploy from anywhere. |
| **Root settings** | `settings.json` | auto | The only two supported keys: `agent: coordinator` (the loop owner is the main-thread default) and a `subagentStatusLine`. |
| **User config** | `plugin.json → userConfig` | — | Asked at enable time: **`default_model`** (export as `CMA_MODEL` for headless builds — coordinator stays opus) and **`evaluator_strictness`** (`standard` / `strict` / `panel`, read by the evaluators via `${user_config.evaluator_strictness}`). |

> **What stays per-agent (no global override exists):** `model`, `tools`, and `skills` are
> declared in each agent's own frontmatter. The one exception is `settings.json`'s `agent` key,
> which promotes a single agent to the main thread. Plugin agents deliberately do **not**
> carry `hooks`/`mcpServers`/`permissionMode` frontmatter — those fields are ignored when an
> agent loads from a plugin.

---

## Two surfaces, one source

| | Local (Cowork / Claude Code) | Managed Agents (headless) |
|---|---|---|
| Trigger | `/agent-team:start` → a workflow command | steering event via `POST /v1/agents` |
| Orchestration | the workflow command drives `Task` delegation | `build.py` → orchestrator + depth-1 leaves |
| Source prompt | `agents/workflows/<wf>.md` | **the same file**, read by `build.py` |
| Role agents | `agents/specialists/**` | same md → each leaf's `system.text` |
| Approval | interactive (`AskUserQuestion`) | output staged in `./out/`, human sign-off |

---

## Low-code platform model: Agent → Project → Session → Context

This scaffold is the **fork-and-edit template** for an agent low-code platform: a user forks it and
edits only `cma.yaml` / md / json to define **Memory, Knowledge, Dreams, and per-agent Context** —
never touching the API. One **Agent** (this fork) runs many **Projects**; each Project runs many
**Sessions**; **Context lives only inside one session**. Memory `scope` (`agent`/`project`/`session`)
decides which sessions share a store. Chinese docs:
[`docs/platform-design.zh.md`](docs/platform-design.zh.md) (design) · [`docs/platform-guide.zh.md`](docs/platform-guide.zh.md) (how-to).

```
Agent (this fork) ── agent-scope memory/knowledge (shared by all projects)
 └─ Project ──────── project-scope memory/knowledge (isolated per project)
     └─ Session ──── one task; session-scope scratch
         └─ Context  ephemeral — gone when the session ends
```

`cma.yaml` has `agent:` (identity + agent-scope memory/knowledge), `memory_stores:` /
`knowledge:` catalogs (each tagged `scope:`), and `projects:` (each lists its memory/knowledge +
workflows). `build.py` iterates **projects × workflows** and prints each session's `resources[]`
with scope-aware id placeholders (`${MEMSTORE_<KEY>__<PROJECT>}` etc.).

## Memory, knowledge, isolated context & dreams (Managed Agents)

The headless surface adds four Managed-Agents capabilities — see
[`docs/memory-and-dreams.md`](docs/memory-and-dreams.md) for the full, citation-backed guide.

### Typed memory: Fact · Rule · Learned · Warning

Every durable memory the team writes is one of four types (full taxonomy, entry
format, and filing rules in [`memory/README.md`](memory/README.md)):

| Type | Captures | Litmus test | Who writes |
|---|---|---|---|
| **`[FACT]`** | verifiable project/world state, decisions, glossary | could a script check it? | any role, with `source:` |
| **`[RULE]`** | binding must/never constraints | does violating it fail a review? | **human sign-off only** (coordinator escalates) |
| **`[LEARNED]`** | distilled experience, with `evidence:` + `apply:` | would it change how I act next time? | the role that lived it |
| **`[WARNING]`** | a pitfall with a concrete `trigger:` + `then:` | is there a trigger condition? | the role that hit it / coordinator |

The types map onto the stores: `team-standards` holds RULE+FACT (read-only — no
agent can relax a rule mid-sprint), `project-context` holds FACT+LEARNED,
`evaluator-calibration` holds LEARNED+WARNING (the judge's private skepticism
triggers). Each store's `seed:` in `cma.yaml` points at a worked example under
`memory/seeds/`, uploaded as the store's first memory at deploy time
(`cma-deploy`); each role's `## Memory` section says which types it reads and
writes. The lifecycle is owned: roles append, the **coordinator** escalates
LEARNED→RULE (human gate), retires fixed WARNINGs, and schedules **dreams** to
consolidate the rest.

- **Memory stores** are markdown collections attached **at session creation**
  (`resources[]`, mounted under `/mnt/memory/`), not fields on the agent. Scopes are a
  *pattern* of which store you attach with what `access`:
  - **Global** — `team-standards`, `read_only`, attached to every session (house standards).
  - **Project** — `project-context`, `read_write`, per project, outlives any session.
  - **Per-agent** — `evaluator-calibration`, attached only to the evaluator's session (its private memory).
  `cma.yaml` declares a `memory_stores:` catalog; workflows set `session_memory:` (global+project)
  and leaves set `memory:` (per-agent). `build.py` emits the session `resources[]` stanza —
  run `python3 scripts/cma/build.py deliver-feature` to see all three resolve.
- **Knowledge / RAG** — there is **no native vector index**. Knowledge = documents mounted in
  the sandbox (uploaded `file` resources or a `github_repository`), and "retrieval" = the agent's
  `grep`/`glob`/`read` over them (plus `web_search`/`web_fetch`). For semantic search, expose a
  vector DB as an **MCP server**. Mount the corpus `read_only`; let memory hold what the agent concludes.
- **Isolated context** — a `multiagent` coordinator runs each sub-agent in its **own
  context-isolated thread** with its own model/tools/MCP. For a truly private-memory agent,
  give it its own agent definition *and* its own session with only its store attached.
- **Dreams** — an async job that reads one store + past sessions and produces a **new,
  reorganized** store (input untouched). The coordinator schedules a dream over the
  calibration/project memory, human-reviewed before adoption.

```
global   →  team-standards        (read_only,  every session)
project  →  project-context       (read_write, this project)
per-agent → evaluator-calibration (read_write, evaluator's session only)
```

---

## Make it your own

1. **Rename or specialize the roles** for your vertical — keep the invariant that
   *the agent that produces is never the agent that judges* (see `docs/agent-roster.md`).
2. **Define the evaluator's dimensions.** The single most important customization:
   replace the four generic grading dimensions in `evaluator.md` (and five in
   `design-evaluator.md`) with criteria that turn "is this good?" into concrete,
   gradable terms for your domain.
3. **Copy `deliver-feature.md`** to one workflow per deliverable type; register
   each under `workflows:` in `scripts/cma/cma.yaml`.
4. **Add domain skills** under `skills/<category>/`; reference them from an
   agent's `skills:` frontmatter (resolved by name — no copying, no sync).
5. **Rewrite `rules/`** for your surfaces (which directory belongs to which role).
6. `cma-check && python3 scripts/cma/build.py` to validate + preview.

## Design invariants (enforced by build.py, verifiable in the dry-run)
- **One source, two surfaces** — md body is the only prompt; CMA derives, never copies.
- **One-level delegation** — every leaf is `callable_agents: []`; no nesting.
- **The producer never judges** — Generator builds, Evaluator judges; verdicts are binding.
- **One writer per surface** — Generator → `src/`, resolver → `./out/` (see `rules/`).
- **Untrusted input is data** — reader leaves carry an `output_schema`.
- **Model parameterized** — `${CMA_MODEL:-sonnet}`; upgrading is one line.

## Files

```
.claude-plugin/plugin.json    manifest (identity + agent list + userConfig)
agents/**/*.md                5 roles + 1 workflow (single source of truth)
skills/**/SKILL.md            3 reference skills, by category
commands/*.md                 /start /status /workflows:deliver-feature
hooks/hooks.json + *.sh       5 events wired; session-start injects rules/
rules/*.md                    working-surface (src/) · deliverable-package (out/)
.mcp.json  .lsp.json          MCP + LSP registration
monitors/  output-styles/     background monitor · loop-verdict style
bin/cma-check  bin/cma-deploy PATH executables
settings.json                 agent=coordinator + subagentStatusLine
knowledge/house-style.md      agent-scope knowledge example
scripts/cma/                  check.py · build.py · deploy.py · cma.yaml · schemas/
docs/                         roster · coordination rules · memory & dreams · zh platform docs
```
