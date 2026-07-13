---
paths:
  - "src/**"
---

# Working Surface Rules

`src/` is the **Generator's** working surface. Only the Generator writes here.

- The Generator writes only under `src/` — never under `./out/` (that belongs to
  the resolver/packager).
- The Evaluator and Design Evaluator are read-only — they never write to `src/`.
- One writer per surface: no two agents write the same file. If two pieces of
  work would touch the same file, sequence them through one Generator pass.
- Every change must trace to an acceptance criterion in the approved sprint
  contract. If a change has no criterion, it is out of scope — flag it, don't ship it.
