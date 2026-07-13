---
description: Deliver one feature end to end — plan, challenge the plan, build, challenge the build, package for sign-off
argument-hint: "[the deliverable, e.g. 'CSV import for the settings page']"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Task, AskUserQuestion
model: sonnet
---

# Deliver Feature (local surface)

Run the `deliver-feature` workflow interactively. Same Planner → Generator →
Evaluator loop as the Managed-Agent deployment (`scripts/cma/`), with approval
at each gate.

If no deliverable is given, ask "What should the team deliver?" and stop.

Load `agents/workflows/deliver-feature.md` for the contract, then delegate with
`Task` — **one level only**:
`planner` (sprint contract) → `design-evaluator` (APPROVE/REVISE) →
`generator` (build under `src/`) → `evaluator` (PASS/FAIL) → package to `./out/`.

Use `AskUserQuestion` to approve before each gate. A REVISE loops back to the
planner; a FAIL loops back to the generator. Nothing packages until the build
verdict is PASS, and nothing ships without the user's sign-off.
