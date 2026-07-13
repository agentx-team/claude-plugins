---
name: blackbox-acceptance
description: Acceptance-test a deployed product as a black box — drive the live UI and API, then verify observability and logs in Grafana — judging UI consistency, API consistency + stability, observability coverage, and log coverage WITHOUT seeing source. Use by the e2e-tester. Triggers on "acceptance test", "e2e test the deployed product", "is the live service correct", "black-box test".
---

# Black-Box Acceptance

How to judge a *running* product from the outside, with only its URLs. You never read the code —
you verify behavior and the signals the system emits.

## Inputs (and only these)

- **Product URL** (live frontend), **API base URL** (ConnectRPC/HTTP), **Grafana URL**.
- The contract's **acceptance criteria** as the definition of "done".
- No repository, no source, no implementation detail.

## 1. UI consistency (browser)

- Walk every acceptance-criterion user flow end to end. Capture a screenshot + the console for each.
- Check cross-page/state consistency (labels, layout, empty/error/loading states), reload
  stability, and the auth flow (unauthenticated access redirects to login; 401 handled).
- FAIL on: a broken criterion flow, console errors, inconsistent state, or UI that contradicts the API.

## 2. API consistency & stability (HTTP/RPC)

- For each RPC: correct response shape and status/error codes; the auth boundary (public vs
  authenticated → **401 without a session**); idempotency where promised.
- Edge inputs: empty / oversized / malformed each return a **named error, no crash**.
- Stability: a short bounded burst (e.g. N concurrent × M rounds) — measure p95/p99 latency vs the
  SLO and error rate; repeat a call to check determinism.
- FAIL on: wrong shape/code, auth leak, latency over SLO, flakiness, or a crash under load.

## 3. Observability coverage (Grafana → Prometheus/Tempo)

- The burst above is *deliberate signal generation*. Now open Grafana and confirm it shows up:
  - RED metrics (Rate / Errors / Duration) present **per RPC**;
  - a request you just made appears as a **trace in Tempo**, end to end;
  - dashboards reflect the load you generated.
- FAIL on: a missing metric/panel, no trace for a request you made, or traffic that leaves no mark.

## 4. Log coverage (Grafana → Loki)

- Find the logs for the requests you made: structured (JSON), with service / level / request-id /
  trace-id, and **error detail on the failures you induced**.
- Correlate one concrete request → its trace → its log line.
- FAIL on: missing logs, unstructured logs, silent error paths, or no trace/request correlation.

## Evidence & verdict

Every finding cites the **URL + the exact request + the observed response/screenshot/panel** —
never the code. Score the four dimensions against their hard bars; verdict **PASS/FAIL** on the
first line with the scored table. Route a FAIL: UI/API/log gaps → engineer; observability wiring
gaps → operator.

## Hard rule

If you ever need to look at source to explain a finding, you're out of role. Re-state it as an
**observable** defect (what a user/integrator sees), or mark the dimension uncertain → FAIL.
