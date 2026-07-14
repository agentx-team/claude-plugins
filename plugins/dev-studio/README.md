# dev-studio

A **cloud-native software delivery agent team** as a Claude Code plugin. Seven roles span the full
**Build → Ship → Accept → Promote** lifecycle for services in one team monorepo derived from
**[github.com/aws300/scaffold](https://github.com/aws300/scaffold)** — proto-first ConnectRPC
backends (Go / Python) + a SolidJS frontend + a Helm chart for Envoy Gateway and AWS IRSA — built,
shipped to the team's Kubernetes cluster, accepted black-box, and taken to market.

Structurally it follows the [`agent-team-scaffold`](../agent-team-scaffold/) reference layout
(same plugin surface: manifest, agents, skills, commands, hooks, rules-via-hook, MCP, settings,
userConfig, CMA deploy layer) — this is the scaffold instantiated for one vertical:
cloud-native service delivery.

## How to use

### 1. Install the plugin

Add the AgentX marketplace (once) and install:

```bash
claude plugin marketplace add agentx-team/claude-plugins
claude plugin install dev-studio@agentx-plugins
```

Or, working from a local checkout:

```bash
claude plugin marketplace add /path/to/claude-plugins   # repo root (the marketplace)
claude plugin install dev-studio@agentx-plugins
```

On enable, the plugin asks for two **userConfig** values (both have defaults, just press Enter):
`default_model` (the Sonnet-tier roles' model — the coordinator stays on opus) and
`reviewer_strictness` (`standard` / `strict` / `panel`).

Requirements: bash + `git` (hooks), `python3` (+ `pip install pyyaml` for the CMA build layer).
No Node, no credentials. The `.mcp.json` registers the GitHub MCP server (HTTP) — the team
monorepo lives on GitHub; authorize it on first use or remove the entry if you don't need it.

### 2. Run the lifecycle

```
/dev-studio:start                        # intake → routes to the right workflow
/dev-studio:workflows:deliver-service    # plan → build → review → package
/dev-studio:workflows:ship-service       # package for the cluster → release gate
/dev-studio:workflows:accept-service     # black-box e2e acceptance of the live service
/dev-studio:workflows:promote-service    # slides + market assessment → accuracy gate
/dev-studio:status                       # read-only lifecycle state
```

The full lifecycle: **deliver → ship → [human deploys] → accept → promote**. For `accept-service`,
have the **product URL, API URL, and Grafana URL** ready — the tester sees nothing else.

### Dispatch shorthands

Two generic dispatchers plus a mention shorthand cover ad-hoc use:

```
/dev-studio:workflow deliver-service orders API      # any workflow by name (= workflows:* above)
/dev-studio:agent marketer 为 orders 服务做市场评估    # one role directly, skipping the gates
@marketer 为 orders 服务做市场评估                     # same thing as a mention (rules/agent-dispatch.md)
@agent-dev-studio:marketer …                          # Claude Code's native agent mention
```

`/dev-studio:agent` (and the `@role` mention) is a *direct* dispatch: one role, one delegation,
no workflow gates — the reply notes which gate was skipped. Slash commands cannot address agents
directly (`/dev-studio:marketer` is not a thing); agents are reached by delegation, which is what
these dispatchers do for you.

### 3. Preview / deploy the CMA surface (optional)

```bash
python3 scripts/cma/check.py            # validate manifest, skills, no nesting
python3 scripts/cma/build.py            # dry-run: print resolved CMA JSON for every workflow
python3 scripts/cma/build.py --model opus
python3 scripts/cma/build.py --post     # upload skills + POST /v1/agents (wire to your deploy)
```

## The core idea: separate the producer from the judge

LLMs grade their own output leniently. So the agent that **generates** is never the agent that
**judges**. Builders (`engineer` / `operator` / `marketer`) make things; separately-tuned skeptics
(`reviewer`, and the black-box `e2e-tester`) try to break them before they reach users.

```
deliver-service:  planner ─▶ reviewer(plan) ─▶ engineer ─▶ reviewer(build) ─▶ package
                     ▲REVISE                       ▲FAIL
ship-service:     operator ─▶ reviewer(release GO/NO-GO) ─▶ package
                                  ▲NO-GO
   ── a human operator applies the deploy plan; the service goes live ──
accept-service:   e2e-tester (BLACK-BOX: product/API/Grafana URLs, no source) ─▶ PASS/FAIL ─▶ package
                                  ▲FAIL → engineer (UI/API/log) or operator (observability)
promote-service:  marketer ─▶ reviewer(fabrication/accuracy GO/NO-GO) ─▶ package
                                  ▲NO-GO
```

## Roles

| Role | Agent | Model | Produces |
|------|-------|-------|----------|
| 规划员 Planner | `planner` | sonnet | service contract with binary acceptance criteria |
| 工程师 Engineer | `engineer` | sonnet | backend + frontend + tests (under `src/`) |
| 评审员 Reviewer | `reviewer` | sonnet | APPROVE/REVISE · PASS/FAIL · GO/NO-GO |
| 运维工程师 Operator | `operator` | sonnet | Helm chart + route + IRSA + observability + deploy/rollback plan |
| 端到端测试工程师 E2E Tester | `e2e-tester` | sonnet | **black-box** acceptance PASS/FAIL from live URLs (no source) |
| 市场推广 Marketer | `marketer` | sonnet | promo deck (slides/pptx) + cited market assessment |
| 协调员 Coordinator | `coordinator` | opus | lifecycle ownership + anti-leniency calibration |

Seven roles on purpose — see [`docs/agent-roster.md`](docs/agent-roster.md) for why backend/
frontend/test collapse into one `engineer` and the gates into one `reviewer`, yet the black-box
`e2e-tester` and the `marketer` each earn a standing role (a distinct trust boundary and a distinct
lifecycle stage).

The `e2e-tester` is special: it runs with **no repository file tools at all** — only web tools —
so it judges the *running* product (UI consistency, API consistency + stability, observability
coverage, log coverage) purely from the product URL, API URL, and Grafana URL, and can never see
the source. The `marketer` prefers the team slides system (`git@github.com:aws300/slides.git`) and
falls back to `ppt-master` only for a required `.pptx`.

## The repo is the process spec — so the team self-evolves

The agents do **not** re-explain how to build, test, or deploy. They read and obey the scaffold
repo's own files, because **code is the best explanation**:

| The "how" | Lives in |
|-----------|----------|
| Dev loop + coding standards + pre-submission checks | `CONTRIBUTING.md` |
| Proto-first stub generation | `protos/Makefile` (`cd protos && make`) |
| Image build + chart publish + deploy | `scripts/deploy.sh` |
| Authoritative lint/test/build/deploy gates | `.github/workflows/` |
| Helm chart shape (Envoy Gateway + IRSA) | `charts/` |

When the repo's process changes, the agents follow automatically — no prompt edits. The team
grows by editing the **repo and its CI**, not by adding more agents.

## Directory layout

Standard plugin layout, same shape as `agent-team-scaffold` (no `.claude/` directory — the
plugin surface itself carries the governance):

```
dev-studio/
├── .claude-plugin/
│   └── plugin.json             ★ the manifest — identity, explicit agent list, userConfig
├── agents/
│   ├── specialists/            # the seven role definitions (md = single source of truth)
│   │   ├── planning/planner.md
│   │   ├── generation/engineer.md
│   │   ├── evaluation/reviewer.md
│   │   ├── ops/operator.md
│   │   ├── acceptance/e2e-tester.md     # black-box: web tools only, no source
│   │   ├── marketing/marketer.md
│   │   └── coordination/coordinator.md
│   └── workflows/              # deliver-service, ship-service, accept-service, promote-service
├── commands/                   # local entry points: start, status, agent, workflow, workflows/*
├── skills/                     # spec-authoring, adversarial-review, blackbox-acceptance,
│                               #   webapp-testing, market-assessment, promo-deck, deploy-pipeline,
│                               #   scaffold-build, google-search, loop-status, wiki (+framework)
├── hooks/
│   ├── hooks.json              # SessionStart · SubagentStart/Stop · PreToolUse(Bash) · PostToolUse(Write|Edit)
│   └── *.sh                    # session-start (injects rules/) · log-agent · validate-push · validate-manifest
├── rules/                      # always-on guardrails, injected by the SessionStart hook
│   ├── working-surface.md      #   src/ — engineer/operator write; reviewer read-only
│   ├── deliverable-package.md  #   out/ — package contents per workflow; nothing applied live
│   └── agent-dispatch.md       #   @role mention shorthand → Task delegation
├── .mcp.json                   # one MCP server: github (the monorepo lives on GitHub)
├── scripts/cma/                # the headless deploy layer (build.py + check.py + cma.yaml)
│   └── schemas/service-contract.json
├── memory/                     # typed-memory taxonomy + seed files
│   ├── README.md               #   [FACT]/[RULE]/[LEARNED]/[WARNING] — who writes what, where
│   └── seeds/*.md              #   per-store seeds (incl. two PRIVATE judge calibration stores)
├── docs/                       # agent-roster, coordination-rules
└── partner-built/              # extension point for team sub-plugins
```

**Rules note:** the plugin spec has no auto-loaded rules directory, so `rules/*.md` are injected
into context by the SessionStart hook (zero model tokens). Forking this as a *project* instead of
a plugin? Copy `rules/` to `.claude/rules/` and Claude Code loads them natively, scoped per-path.

## Plugin surface

| Capability | File | What it does |
|---|---|---|
| **Manifest** | `.claude-plugin/plugin.json` | Identity + the explicit agent list (preserves the nested layout) + `userConfig` (`default_model`, `reviewer_strictness`). |
| **Agents** | `agents/**/*.md` | 7 roles + 4 workflow orchestrators; frontmatter carries `tools`/`model`/`skills`/`memory`. |
| **Skills** | `skills/**/SKILL.md` | Methods by category, loaded on demand; referenced from agent frontmatter by name. |
| **Commands** | `commands/*.md` | `/dev-studio:start`, `/dev-studio:status`, `/dev-studio:workflows:*`. |
| **Hooks** | `hooks/hooks.json` | SessionStart injects lifecycle context + `rules/`; SubagentStart/Stop audit trail; PreToolUse warns on live-cluster mutations (`helm upgrade`, `kubectl apply`, `docker push`, `git push`); PostToolUse re-validates the CMA manifest after agent/skill edits. |
| **Rules** | `rules/*.md` | One-writer-per-surface + nothing-applied-live guardrails. |
| **MCP** | `.mcp.json` | GitHub MCP server (HTTP) for the team monorepo. |
| **CMA layer** | `scripts/cma/` | `check.py` validates · `build.py` derives deploy JSON + session `resources[]` from the same md · `cma.yaml` declares the topology and the memory-store catalog. |
| **Typed memory** | `memory/` | Every durable memory is `[FACT]` / `[RULE]` / `[LEARNED]` / `[WARNING]` (taxonomy + filing rules in `memory/README.md`). Stores: `team-standards` (RULE+FACT, read-only — includes the observability convention as facts), `project-context` (FACT+LEARNED), and **two private judge stores** — `reviewer-calibration` and `e2e-calibration` (LEARNED+WARNING) — never visible to producers or to each other. Seeds under `memory/seeds/` upload at deploy; each role's `## Memory` section defines its read/write habits; the coordinator owns LEARNED→RULE escalation (human gate) and WARNING expiry. |

> **No plugin `settings.json` on purpose.** The plugin-level `settings.json` supports exactly two
> keys — `agent` (promote one agent to the main thread) and `subagentStatusLine` — and dev-studio
> uses neither: the coordinator is woken on demand (`/dev-studio:agent coordinator …` or
> `@coordinator …`) instead of owning every session. See `agent-team-scaffold` for a working
> example of the `settings.json → agent` capability.

## Two surfaces, one source

- **Local (Claude Code / Cowork):** the `agents/`, `commands/`, and `skills/` md files. Run
  `/dev-studio:start` and the workflow commands interactively, with an approval gate at each step.
- **Headless (Claude Managed Agents):** `scripts/cma/build.py` reads the *same* md assets and
  derives the CMA deploy JSON — no per-agent yaml. `cma.yaml` declares only the topology.

## Design invariants (non-negotiable)

1. **Producer ≠ judge** — generators never self-certify.
2. **The acceptance judge is black-box** — `e2e-tester` has no source access, only web tools + URLs.
3. **Marketing never outruns the product** — only shipped capabilities, only cited market claims.
4. **Verdicts are binding** — REVISE/FAIL/NO-GO loop back; nothing ships without sign-off.
5. **One writer per surface** — engineer/operator/marketer → `src/`, packager → `./out/`, judges read-only.
6. **One-level delegation** — leaves never nest.
7. **The repo is the process spec** — follow its scripts/CI; proto-first; never hand-edit generated code.
8. **Nothing applied or published live** — deploys/pushes/deck publishing are staged for a human
   (enforced by the `validate-push` hook + `rules/deliverable-package.md`).

See [`docs/coordination-rules.md`](docs/coordination-rules.md) for the full set.
