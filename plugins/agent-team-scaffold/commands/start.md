---
description: Start here — clarify what you want delivered, then route into the Planner → Generator → Evaluator loop
argument-hint: "[what you want delivered, e.g. 'a CSV import feature']"
---

The requirements-intake entry point for this agent team. Most work runs *inside*
the loop; this command figures out what you need and hands you to the workflow.

If a request is provided, use it; otherwise ask: "What would you like the team to
deliver or improve?"

Then clarify scope just enough to start the **Planner**, and route to a workflow:

| If the goal is… | Route to |
|---|---|
| a single end-to-end deliverable | `/agent-team:workflows:deliver-feature` |
| (add your vertical's workflows here as you copy `deliver-feature.md`) | … |

Do not plan or implement here — that happens inside the loop:
`planner` writes the sprint contract → `design-evaluator` challenges it
(APPROVE/REVISE) → `generator` builds → `evaluator` challenges the build
(PASS/FAIL) → resolver packages for sign-off. Ask only the few questions needed
to pick the workflow and frame the Planner's input (goal, scope, constraints).
