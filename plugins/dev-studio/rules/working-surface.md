---
paths:
  - "src/**"
---

# Working Surface Rules

`src/` is the **Engineer's / Operator's** working surface. Only they write here.

- Generators (engineer, operator) write only under `src/` — never under `./out/` (that belongs
  to the resolver/packager).
- The Reviewer is read-only — it never writes to `src/` (only its own verdict file).
- One writer per surface: no two agents write the same file. If two pieces of work would touch
  the same file, sequence them through one Generator pass.
- Every change must trace to an acceptance criterion in the approved service contract. If a
  change has no criterion, it is out of scope — flag it, don't ship it.
- The process is the scaffold repo's own scripts and CI (`CONTRIBUTING.md`, `protos/Makefile`,
  `scripts/deploy.sh`, `.github/workflows/`) — follow them; don't reinvent or re-explain them.
