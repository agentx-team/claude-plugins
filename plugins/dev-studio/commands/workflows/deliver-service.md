---
description: Deliver a service end to end — plan, build (backend + frontend + tests) from the scaffold, then adversarial code + security review, packaged for sign-off
argument-hint: "[the service, e.g. 'orders API: create + list orders']"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Task, AskUserQuestion
model: sonnet
---

# Deliver Service (local surface)

Run the `deliver-service` workflow interactively. Same Planner → Generator → Evaluator loop as
the Managed-Agent deployment (`scripts/cma/`), with approval at each gate.

If no service is given, ask "What should the studio deliver?" and stop. If a design package from
design-service exists, use its contract.

Load `agents/workflows/deliver-service.md` for the contract, then delegate with `Task`
— **one level only**:
`tech-lead` (service contract) → `test-engineer` (failing tests first) +
`backend-engineer` (ConnectRPC backend, proto-first) + `frontend-engineer` (SolidJS SPA), all
under `src/` → `code-reviewer` (PASS/FAIL) + `security-reviewer` (PASS/FAIL) → package to `./out/`.

Use `AskUserQuestion` to approve before each gate. A FAIL from either reviewer loops back to the
responsible engineer. Nothing packages until BOTH verdicts are PASS, and nothing ships without
the user's sign-off. proto-first (API in `protos/` then `cd protos && make`); generated code is
never hand-edited.
