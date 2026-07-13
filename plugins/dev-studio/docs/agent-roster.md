# Agent Roster — dev-studio

Seven roles spanning the full **Build → Ship → Accept → Promote** lifecycle. Each agent's
definition lives under `agents/specialists/`. The roster is deliberately small: the team evolves by
editing the **scaffold repo** (github.com/aws300/scaffold) — its scripts and CI are the process
spec — not by piling on agents. The two judge roles (`reviewer`, `e2e-tester`) never build, and the
builders never judge their own work.

## The roster

| Role | Agent | Directory | Model | Produces |
|------|-------|-----------|-------|----------|
| 规划员 Planner | `planner` | `planning/` | sonnet | `service_contract.json` (binary acceptance criteria) |
| 工程师 Engineer | `engineer` | `generation/` | sonnet | backend + frontend + tests under `src/` |
| 评审员 Reviewer | `reviewer` | `evaluation/` | sonnet | **APPROVE/REVISE** (plan), **PASS/FAIL** (build), **GO/NO-GO** (release & promo) |
| 运维工程师 Operator | `operator` | `ops/` | sonnet | Helm chart + route + IRSA + observability + deploy/rollback plan |
| 端到端测试工程师 E2E Tester | `e2e-tester` | `acceptance/` | sonnet | **black-box** acceptance verdict (**PASS/FAIL**) from live URLs |
| 市场推广 Marketer | `marketer` | `marketing/` | sonnet | promo deck (slides/pptx) + cited market assessment |
| 协调员 Coordinator | `coordinator` | `coordination/` | **opus** | lifecycle ownership + anti-leniency calibration |

## The lifecycle

```
deliver-service:  planner → reviewer(plan) → engineer → reviewer(build)        [code, tested, reviewed]
ship-service:     operator → reviewer(release GO/NO-GO)                        [chart + observability staged]
   ── a human operator applies the deploy plan; the service goes live ──
accept-service:   e2e-tester (black-box; product/API/Grafana URLs only)        [PASS/FAIL acceptance]
promote-service:  marketer → reviewer(fabrication/accuracy GO/NO-GO)           [deck + market assessment]
```

## The black-box tester is special

`e2e-tester` runs under a dedicated `tester` role that gets **no repository file tools at all** —
only `websearch`/`webfetch`. It is handed just three URLs (product, API, Grafana) and the
acceptance criteria, and judges UI consistency, API consistency + stability, observability
coverage, and log coverage purely from observable behavior. Because it never built the product and
never sees its source, producer ≠ judge holds with a single role — no second reviewer needed in
`accept-service`. This is also a security property: the acceptance judge can't be biased by, or leak,
implementation detail.

## The marketer closes the loop to market

`marketer` produces go-to-market materials for a shipped product: a promo deck (preferring the team
slides system `git@github.com:aws300/slides.git`, falling back to `ppt-master` only for a required
pptx) and a search-driven market assessment (comparable products, positioning, recommended
directions — every claim cited). The `reviewer` then gates it for fabrication and accuracy vs. what
actually shipped, so marketing never outruns the product.

## Why this set (and not more)

The producer↔judge separation is the one invariant that must never collapse: **the agent that
generates is never the agent that judges**. Beyond that, roles are merged aggressively, and each
role earns its place by owning a distinct *stage of the lifecycle* or a distinct *trust boundary*:

- **One Engineer, not three.** Backend / frontend / tests are surfaces of one builder, not
  separate agents — the *repo's* per-component standards (`CONTRIBUTING.md`, component READMEs)
  already encode the differences. Adding `backend-engineer` / `frontend-engineer` / `test-engineer`
  would duplicate what the repo already says.
- **One Reviewer, many gates.** Plan review, code review, security review, the release gate, and
  the promo accuracy gate are the same skeptical discipline applied at different points; the
  `reviewer` scores against hard bars in one pass and weights security higher on a new
  authenticated RPC or IRSA change (the coordinator sets intensity).
- **A separate E2E Tester, because the trust boundary differs.** The reviewer is white-box (reads
  code); the e2e-tester is **black-box (no source at all)**. They catch different failure classes —
  the reviewer finds *how* the code is wrong; the tester finds *that* the deployed system behaves
  wrong. Folding them would lose the black-box guarantee, so this is a real role, not a duplicate.
- **A separate Marketer, because it owns the last lifecycle stage.** Go-to-market (slides + market
  assessment) is genuinely different work from building software, with its own tools
  (`aws300/slides`, `ppt-master`) and its own failure mode (fabricated claims) — which the reviewer
  gates.
- **No git-master / debugger / explorer / writer.** Git, debugging, search, and docs are part of
  every role's normal work and are covered by the repo's CI and conventions — they don't earn a
  standing agent.

## The scaffold repo is the process spec

The agents don't re-explain how to build, test, or deploy. They reference and obey the team
monorepo's own files — **github.com/aws300/scaffold**:

- `CONTRIBUTING.md` — development loop + per-component standards + pre-submission checklist
- `protos/Makefile` — proto-first generation (`cd protos && make`)
- `scripts/deploy.sh` — image build + chart publish + deploy shape
- `.github/workflows/` — the authoritative lint/test/build/deploy gates
- `charts/` — the Helm chart shape (Envoy Gateway + IRSA)

Code is the explanation. When the repo's process changes, the agents follow automatically — no
prompt edits needed. That is the self-evolution property.

## Why the Coordinator is Opus

It takes the hardest, multi-document calls: detecting leniency drift in any judge (reviewer or
e2e-tester), adjudicating producer↔judge disputes, keeping the tester in its black-box lane, and
deciding how hard to challenge a given change. Everything else runs on Sonnet. (Model is
parameterized in `scripts/cma/cma.yaml` — upgrading is a one-line change.)

## Extending

Prefer extending the **scaffold repo** (new service, new CI check) over adding agents. If you truly
need a new standing role, keep producer ≠ judge intact and add it under the right
`agents/specialists/<category>/`, then one leaf entry in `cma.yaml`.
