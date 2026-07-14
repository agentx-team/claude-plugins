# project-context — seed (types: FACT, LEARNED)

Project-scope, read-write. This project's decisions and accumulated experience.
The examples below show the shape; the first real sprint replaces them.

[FACT] This project uses the Planner → Design-Evaluator → Generator → Evaluator
loop; the sprint contract (schemas/sprint-contract.json) is the unit of work.
source: sprint 0 setup

[FACT] Deliverables are packaged under ./out/<deliverable>/ with both verdicts
and a sign-off summary; the package is the only hand-off artifact.
source: rules/deliverable-package.md

[LEARNED] Contracts whose criteria say "works correctly" instead of naming the
verifying test get REVISE on first review — write the verification method into
the criterion at planning time.
evidence: (example) sprint 1, design-evaluator REVISE on criteria 2 and 4
apply: planner runs the spec-authoring checklist before submitting a contract

[LEARNED] When a FAIL loops back, resubmitting the full deliverable wastes an
evaluation round — resubmit with a delta note listing exactly what changed per
failed criterion.
evidence: (example) sprint 2, second evaluation round cut from full re-review
to delta review
apply: generator attaches a "changes since last verdict" list on every resubmit
