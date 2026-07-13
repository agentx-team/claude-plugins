---
name: spec-authoring
description: Turn a short request into a sprint contract with binary, testable acceptance criteria. Use when a Planner needs to decompose an ambiguous ask into an implementable spec. Triggers on "write a spec", "plan this feature", "define acceptance criteria", "sprint contract".
---

# Spec Authoring

A method for turning a 1–4 sentence request into a **sprint contract** the
Generator can build against and the Evaluator can grade against.

## The rule that matters most

**Every acceptance criterion must be binary.** If you cannot state in one
sentence how it would be verified (a test, a measurement, a read-through), it is
not a criterion yet — rewrite it until you can.

| Vague (reject) | Binary (accept) |
|---|---|
| "Should feel responsive" | "Input → visible feedback in ≤ 50 ms" |
| "Easy to use" | "A first-time user completes the primary task in ≤ 3 steps without docs" |
| "Handles errors well" | "Empty/oversized/malformed input each produce a named error, no crash" |

## Steps

1. **Clarify scope** — ask only the questions that change scope; do not guess.
2. **Decompose** into the smallest independently shippable chunks (one chunk =
   one Generator pass = one Evaluator verdict).
3. **Be ambitious about scope, conservative about detail** — specify *what* and
   *how it's verified*, not the low-level *how*. Over-specified detail cascades
   errors downstream.
4. **State out-of-scope explicitly** — name the related things this sprint does NOT include.
5. **Flag dependencies** — anything this builds on; mark anything not yet built (scope risk).
6. **Write binary acceptance criteria** with a verification method for each.

## Output

Emit the sprint-contract structure (matches `scripts/cma/schemas/sprint-contract.json`):
deliverable, status, scope, out_of_scope, dependencies, and acceptance_criteria
(each a `{criterion, verification}` pair). Hand to the Design Evaluator before any build.
