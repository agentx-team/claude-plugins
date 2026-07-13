---
name: loop-status
description: Report the current state of the Planner → Generator → Evaluator loop — which stage is active, the last verdict, open issues, and what's blocking. Read-only. Triggers on "loop status", "where are we", "what's blocking", "show progress".
---

# Loop Status

Report the current state of the Planner → Generator → Evaluator loop. Read-only —
do not start or modify work.

## What to report

1. **Active stage** — Plan / Plan-review / Build / Build-review / Package.
2. **Last verdict** — APPROVE/REVISE (plan) or PASS/FAIL (build), with the score table.
3. **Open blocking issues** — from the most recent verdict, if any.
4. **What's next** — the single next action (e.g. "generator to fix 2 blocking
   issues and resubmit to evaluator").
5. **Staged outputs** — anything under `./out/` awaiting human sign-off.

## Format

```
Loop: <deliverable>
Stage: <active stage>
Last verdict: <PASS/FAIL/APPROVE/REVISE> (<n> blocking, <n> advisory)
Blocking: <list or "none">
Next: <single next action>
Awaiting sign-off: <./out/ packages or "none">
```

Keep it concise. If no loop is active, say so.
