# Agent Roster

Each agent has a definition file under `agents/specialists/`. The roster is organized
by **loop role**, not by domain function — this is a domain-agnostic scaffold.
To build your vertical, keep the five roles and either rename them or add
domain specialists that play each role.

## The Planner → Generator → Evaluator loop

| Loop role | Agent | Dir | Model | Verdict it produces |
|---|---|---|---|---|
| Planner | `planner` | `specialists/planning/` | sonnet | sprint contract |
| Design Evaluator | `design-evaluator` | `specialists/evaluation/` | sonnet | **APPROVE / REVISE** (on the plan) |
| Generator | `generator` | `specialists/generation/` | sonnet | the deliverable under `src/` |
| Evaluator | `evaluator` | `specialists/evaluation/` | sonnet | **PASS / FAIL** (on the build) |
| Coordinator | `coordinator` | `specialists/coordination/` | opus | loop ownership + calibration |

### Role assignment per workflow

| Workflow | Planner | Generator | Evaluator(s) |
|---|---|---|---|
| deliver-feature (reference) | planner | generator | design-evaluator (plan) + evaluator (build) |
| *(your workflows here)* | … | … | … |

## Extending the roster for a vertical

Two strategies, mix as needed:

1. **Rename the roles.** A legal team: planner→`matter-scoper`,
   generator→`drafter`, evaluator→`opposing-counsel-sim`. A newsroom:
   planner→`assignment-editor`, generator→`reporter`, evaluator→`fact-checker`.
2. **Add specialists that play a role.** Keep `generator` generic and add
   `frontend-generator`, `api-generator`; keep `evaluator` and add
   `security-evaluator`, `accessibility-evaluator`. Each new expert is one md
   file; register it as a leaf in `scripts/cma/cma.yaml`.

Whatever you add, preserve the invariant: **the agent that produces is never the
agent that judges.** That separation is the whole point of the scaffold.

## Why the Coordinator is Opus

The Coordinator does the hardest reasoning in the system — detecting leniency
drift, adjudicating Generator-vs-Evaluator disputes, and deciding how heavily to
deploy the evaluator for a given task. That is multi-document, high-stakes
judgment, so it runs on the top tier while the producing/judging roles run on
Sonnet. (Model is parameterized in `cma.yaml`; upgrading is a one-line change.)
