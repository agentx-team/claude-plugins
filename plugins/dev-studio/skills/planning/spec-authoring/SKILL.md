---
name: spec-authoring
description: Turn a short service request into a service contract with binary, testable acceptance criteria and a named proto-first API surface. Use when a Tech Lead needs to decompose an ambiguous ask into an implementable contract. Triggers on "write a spec", "plan this service", "define acceptance criteria", "service contract".
---

# Spec Authoring

A method for turning a 1–4 sentence request into a **service contract** the engineers can build
against and the evaluators can grade against — scoped to the cloud-native scaffold.

## The rule that matters most

**Every acceptance criterion must be binary.** If you cannot state in one sentence how it would
be verified (a test, a build/lint command, a measurement, a read-through), it is not a criterion
yet — rewrite it until you can.

| Vague (reject) | Binary (accept) |
|---|---|
| "API should be fast" | "`ListItems` p99 < 150 ms at 100 rps in the integration test" |
| "Secure by default" | "Every RPC except the OIDC handshake returns 401 without a valid session (contract test)" |
| "Handles bad input" | "Empty / oversized / malformed request each return a named ConnectRPC error, no panic" |
| "Observable" | "Each RPC emits a Prometheus counter + histogram and a Tempo span; dashboard panel exists" |

## Steps

1. **Clarify scope** — ask only the questions that change scope: which surfaces (backend-go /
   backend-python / frontend / proto / chart / observability)? which RPCs? authenticated or
   public? new proto package or extend one? needs IRSA / a base-stack store?
2. **Name the API** — list each ConnectRPC method as `package.vN.Service/Method` with a one-line
   description and `public`/`authenticated`. This is what proto-first generation keys off.
3. **Decompose** into the smallest independently shippable slices. One slice = one Generator pass
   = one Evaluator verdict.
4. **Be ambitious about scope, conservative about detail** — specify *what* and *how it's
   verified*, not the low-level *how*. Over-specified detail cascades errors downstream.
5. **State out-of-scope explicitly** and **flag dependencies** (anything not yet built is a
   scope risk — name it).
6. **Write binary acceptance criteria**, each a `{criterion, verification}` pair.

## Output

Emit the service-contract structure (matches `scripts/cma/schemas/service-contract.json`):
`service`, `summary`, `status`, `surfaces`, `apis` (rpc + description + auth), `scope`,
`out_of_scope`, `dependencies`, and `acceptance_criteria`. Hand to the design-evaluator (in
design-service) or to the Generators (in deliver-service) once approved.
