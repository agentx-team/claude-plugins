---
name: loop-status
description: Report the current state of the studio's Plan → Build → Review → Ship loop — active workflow and stage, the last verdict with its score table, open blockers, the single next action, and any ./out/ packages awaiting sign-off. Use for a read-only status check. Triggers on "status", "where are we", "what's next", "loop state".
---

# Loop Status

A read-only status read of the studio's delivery loop. Report concisely; never start or modify
work from this skill.

## What to report

1. **Active workflow & stage** — which of deliver-service / ship-service / accept-service /
   promote-service is running, and which stage it's in (`plan → build → review → package`, or for
   accept `probe → grafana-verify → verdict`, or for promote `author → review → package`). The
   lifecycle order is **deliver → ship → [human deploys] → accept → promote**.
2. **Last verdict** — the most recent APPROVE/REVISE, PASS/FAIL, or GO/NO-GO, with its scored
   dimension table and the agent that issued it.
3. **Open blockers** — outstanding REVISE/FAIL/NO-GO items not yet resolved, each with its
   `file:line` and owner.
4. **Next action** — the single next step (e.g. "backend-engineer to address code-review FAIL
   items 1–3", or "awaiting human sign-off on ./out/orders-api/").
5. **Awaiting sign-off** — packages under `./out/` ready for human review.

## Where to look

- `src/` — work in progress: `service_contract.json`, `src/design/`, the implementation,
  `src/*_verdict.md`, `src/deploy/`, `src/observability/`.
- `./out/` — packaged deliverables awaiting sign-off.
- `out/session-logs/agent-audit.log` — which agents have run (audit trail).
- `git log --oneline -5` and the current branch.

## Output shape

```
Workflow:  deliver-service · stage: review
Last verdict: reviewer FAIL (Spec 2/5 · Correctness 3/5 · Security 4/5 · Cloud-native 4/5)
Blockers:
  1. [HIGH] backend/internal/server/orders.go:88 — empty request panics (no validation)
  2. [HIGH] missing test for criterion "401 without session"
Next: engineer addresses items 1–2, re-submit to reviewer
Awaiting sign-off: (none)
```

Keep it tight and factual — this is a glance at the loop, not an analysis.
