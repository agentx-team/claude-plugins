---
name: scaffold-build
description: |
  Build a service from the team scaffold (github.com/aws300/scaffold) — proto-first ConnectRPC
  backend (Go 1.26 / Python 3.13) + SolidJS frontend — by following the repo's OWN scripts and CI
  rather than re-explaining the stack.

  Use when: implementing a new service or feature, regenerating proto stubs, or running the local
  build/lint/test loop before review. Triggers on "build the service", "implement the backend",
  "scaffold", "regenerate protos", "make the frontend".

  Not for: deploy/Helm packaging (use deploy-pipeline) or black-box acceptance (use webapp-testing).
---

# Scaffold Build

The team builds one monorepo derived from **github.com/aws300/scaffold**. The repo's own files ARE
the build spec — read and obey them; do not invent or re-document the process.

## The source of truth (read these first)

| The "how" | Lives in |
|-----------|----------|
| Dev loop, per-component coding standards, pre-submission checklist | `CONTRIBUTING.md` |
| Proto-first stub generation (Go + TS + Python in one shot) | `protos/Makefile` → `cd protos && make` |
| Authoritative lint / test / build gates | `.github/workflows/lint.yml` |
| Component specifics | `backend/README.md`, `backend-py/README.md`, `frontend/README.md` |

## The development loop

`define protos → generate code → write code → build & verify` — then hand to the reviewer.

1. **Protos first.** If the API surface changes, edit `protos/<pkg>/v1/*.proto`, then `cd protos &&
   make`. **Never hand-edit generated code** (`backend/pkg/pb/`, `frontend/src/gen/`,
   `backend-py/src/app/generated/`).
2. **Write code** under `src/` (one slice at a time; each change traces to an acceptance criterion).
   - Go: ConnectRPC handlers, not raw net/http; modern stdlib; auth via the central `WithAuthFunc`.
   - Python: 3.13 strict typing (PEP 695 `type`, `X | Y`, `Self`, minimal `Any`).
   - Frontend: **SolidJS, not React** — components run once; do not destructure props; no `any`.
3. **Verify with the repo's own commands** until green (fresh output, not a remembered result):
   - `cd backend && go build ./... && go test ./... && golangci-lint run`
   - `cd backend-py && ruff check src/ && ruff format --check src/ && mypy src/`
   - `cd frontend && npm run lint && npm run typecheck && npm run build`

## Cloud-native posture (all backends)

Stateless; state lives in the cluster's existing data services (Postgres/MySQL/Mongo/Redis/MinIO/
EMQX/Temporal); config via env / Helm values, **no hardcoded secrets or endpoints**;
readiness/liveness; graceful shutdown; context + timeouts on outbound calls; emit structured JSON
logs, a metrics endpoint, and propagated trace context so observability can be wired downstream.

## Checklist before handoff

- [ ] Protos regenerated if the API changed; no generated code hand-edited.
- [ ] The repo's build + test + lint + typecheck all pass locally (fresh output).
- [ ] Every change traces to an acceptance criterion; Go and Python backends kept equivalent.
- [ ] No secrets/endpoints hardcoded.
