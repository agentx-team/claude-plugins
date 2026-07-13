---
description: Deliver a service end to end — plan, build (backend + frontend + tests) from the scaffold, then adversarial code + security review, packaged for sign-off
argument-hint: "[the service, e.g. 'orders API: create + list orders']"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Task, AskUserQuestion
model: sonnet
---

# Deliver Service (local surface)

Run the `deliver-service` workflow interactively. Same Planner → Generator → Evaluator loop as
the Managed-Agent deployment (`scripts/cma/`), with approval at each gate.

If no service is given, ask "What should the studio deliver?" and stop.

Load `agents/workflows/deliver-service.md` for the contract, then delegate with `Task`
— **one level only**:
`planner` (service contract) → `reviewer` on the plan (APPROVE/REVISE) →
`engineer` (tests first, then ConnectRPC backend + SolidJS SPA, all under `src/`) →
`reviewer` on the build (code + security, PASS/FAIL) → package to `./out/`.

Use `AskUserQuestion` to approve before each gate. A REVISE loops back to the planner; a FAIL
loops back to the engineer. Nothing packages until the verdict is PASS, and nothing ships without
the user's sign-off. proto-first (API in `protos/` then `cd protos && make`); generated code is
never hand-edited.
