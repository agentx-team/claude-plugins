---
description: Ship a delivered service — Helm chart + Envoy route + IRSA + observability wired into the running platform, then an adversarial release gate. Deploy stays a human action.
argument-hint: "[the service to ship, e.g. 'orders to namespace orders']"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Task, AskUserQuestion
model: sonnet
---

# Ship Service (local surface)

Run the `ship-service` workflow interactively. Same loop as the Managed-Agent deployment
(`scripts/cma/`), with approval at the gate.

If no service is given, ask "Which delivered service should we ship, and to which namespace?"
and stop.

Load `agents/workflows/ship-service.md` for the contract, then delegate with `Task`
— **one level only**: `operator` (chart + route + IRSA + deploy/rollback plan + observability
under `src/deploy/`, mirroring the scaffold repo's `scripts/deploy.sh` and CI, wired into the
cluster's existing Prometheus/Loki/Tempo/Grafana) → `reviewer` (GO/NO-GO) → package to `./out/`.

Use `AskUserQuestion` to approve before packaging. A NO-GO loops back to the operator. **The deploy
itself (helm upgrade / kubectl apply / image push) is never executed here** — the package holds the
operator's deploy plan and rollback plan for a human. Wire into the existing monitoring stack; never
stand up new infra. Pin image digests; no secrets in charts/images.
