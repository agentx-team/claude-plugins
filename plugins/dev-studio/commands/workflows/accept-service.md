---
description: Black-box acceptance of a DEPLOYED service — drive the live UI + API and verify observability + logs in Grafana, without seeing source. PASS/FAIL verdict.
argument-hint: "[product URL, API URL, Grafana URL for the live service]"
allowed-tools: Read, Glob, Grep, Task, AskUserQuestion, WebSearch, WebFetch
model: sonnet
---

# Accept Service (local surface)

Run the `accept-service` workflow interactively, after a human operator has deployed the service
(from a ship-service package) and it is live.

If the URLs aren't given, ask for the **product URL**, the **API base URL**, and the **Grafana
URL**, plus the acceptance criteria — then stop until you have them.

Load `agents/workflows/accept-service.md` for the contract, then delegate with `Task`
— **one level only**: `e2e-tester` (black-box: drives live UI + API, generates a load burst, then
verifies metrics/traces/logs in Grafana — **never reads source**) → package the acceptance report
to `./out/`.

The tester scores four dimensions — UI consistency, API consistency + stability, observability
coverage, log coverage — and issues **PASS/FAIL**. A FAIL routes back: UI/API/log gaps to
deliver-service (engineer), observability wiring gaps to ship-service (operator). Findings cite the
URL + request + observed response, never code. Read-only against live systems — never mutate data.
