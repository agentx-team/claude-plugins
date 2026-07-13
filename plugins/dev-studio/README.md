# dev-studio

A **cloud-native software delivery agent team** as a Claude Code plugin. Seven roles span the full
**Build → Ship → Accept → Promote** lifecycle for services in one team monorepo derived from
**[github.com/aws300/scaffold](https://github.com/aws300/scaffold)** — proto-first ConnectRPC
backends (Go / Python) + a SolidJS frontend + a Helm chart for Envoy Gateway and AWS IRSA — built,
shipped to the team's Kubernetes cluster, accepted black-box, and taken to market.

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

```
dev-studio/
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
├── commands/                   # local entry points: start, status, workflows/*
├── skills/                     # spec-authoring, adversarial-review, blackbox-acceptance,
│                               #   market-assessment, promo-deck, loop-status
├── scripts/cma/                # the headless deploy layer (build.py + check.py + cma.yaml)
│   └── schemas/service-contract.json
├── .claude/                    # settings.json + hooks + rules (local governance)
├── .claude-plugin/             # marketplace.json
├── .mcp.json                   # one MCP server: github (the monorepo lives on GitHub)
├── docs/                       # agent-roster, coordination-rules
└── partner-built/              # extension point for team sub-plugins
```

## Two surfaces, one source

- **Local (Claude Code / Cowork):** the `agents/`, `commands/`, and `skills/` md files. Run
  `/dev-studio:start` and the workflow commands interactively, with an approval gate at each step.
- **Headless (Claude Managed Agents):** `scripts/cma/build.py` reads the *same* md assets and
  derives the CMA deploy JSON — no per-agent yaml. `cma.yaml` declares only the topology.

```bash
python3 scripts/cma/check.py            # validate manifest, skills, no nesting
python3 scripts/cma/build.py            # dry-run: print resolved CMA JSON for every workflow
python3 scripts/cma/build.py --model opus
python3 scripts/cma/build.py --post     # upload skills + POST /v1/agents (wire to your deploy)
```

## Use it

```
/dev-studio:start                        # intake → routes to a workflow
/dev-studio:workflows:deliver-service    # plan → build → review → package
/dev-studio:workflows:ship-service       # package for the cluster → release gate
/dev-studio:workflows:accept-service     # black-box e2e acceptance of the live service
/dev-studio:workflows:promote-service    # slides + market assessment → accuracy gate
/dev-studio:status                       # read-only lifecycle state
```

## Design invariants (non-negotiable)

1. **Producer ≠ judge** — generators never self-certify.
2. **The acceptance judge is black-box** — `e2e-tester` has no source access, only web tools + URLs.
3. **Marketing never outruns the product** — only shipped capabilities, only cited market claims.
4. **Verdicts are binding** — REVISE/FAIL/NO-GO loop back; nothing ships without sign-off.
5. **One writer per surface** — engineer/operator/marketer → `src/`, packager → `./out/`, judges read-only.
6. **One-level delegation** — leaves never nest.
7. **The repo is the process spec** — follow its scripts/CI; proto-first; never hand-edit generated code.
8. **Nothing applied or published live** — deploys/pushes/deck publishing are staged for a human.

See [`docs/coordination-rules.md`](docs/coordination-rules.md) for the full set.
