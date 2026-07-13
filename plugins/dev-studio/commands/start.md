---
description: Start here — clarify what you want, then route into the right studio workflow across the full lifecycle (build → ship → accept → promote)
argument-hint: "[what you want, e.g. 'an orders API service', 'ship orders', 'accept orders', 'promote orders']"
---

The requirements-intake entry point for the dev studio. Most work runs *inside* the workflows;
this command figures out what you need and hands you to the right one.

The team builds one cloud-native monorepo derived from **github.com/aws300/scaffold** (proto-first
ConnectRPC backends + SolidJS frontend + Helm/Envoy/IRSA), ships it onto the team's cluster, then
accepts and promotes it.

If a request is provided, use it; otherwise ask: "What stage are we at — build, ship, accept, or
promote a service?"

Route to a workflow (the lifecycle runs in this order):

| If the goal is… | Route to |
|---|---|
| **build** a service end to end (plan → backend + frontend + tests → review) | `/dev-studio:workflows:deliver-service` |
| **ship** a delivered service (Helm + route + IRSA + observability, release gate) | `/dev-studio:workflows:ship-service` |
| **accept** a *deployed* service (black-box e2e test of the live URLs + Grafana) | `/dev-studio:workflows:accept-service` |
| **promote** a shipped product (slides/pptx + market assessment) | `/dev-studio:workflows:promote-service` |

The full lifecycle: **deliver → ship → [human deploys] → accept → promote**.

Do not plan or implement here — that happens inside the loops:
- *deliver:* `planner` → `reviewer`(APPROVE/REVISE) → `engineer` → `reviewer`(PASS/FAIL)
- *ship:* `operator` → `reviewer`(GO/NO-GO)
- *accept:* `e2e-tester` (black-box, sees only product/API/Grafana URLs — never source) → PASS/FAIL
- *promote:* `marketer` (slides via aws300/slides; market assessment) → `reviewer`(GO/NO-GO)

For accept, collect the **product URL, API URL, and Grafana URL** before routing. Ask only the few
questions needed to pick the workflow and frame the role's input.
