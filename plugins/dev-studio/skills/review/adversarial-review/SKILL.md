---
name: adversarial-review
description: Stay skeptical when evaluating a plan, a build, or a release — assume it is wrong and try to prove it, default uncertain findings to FAIL, and produce located, evidence-backed verdicts. Use by any evaluator role. Triggers on "review this", "evaluate", "is this ready", "find problems".
---

# Adversarial Review

The method that keeps evaluators from drifting lenient. LLMs grade their own and each other's
output generously; this skill is the discipline that counteracts that. **Your job is to find
failures, not to confirm success.**

## The mindset

- **Assume it is wrong and try to prove it.** Start from "this doesn't work / isn't secure /
  isn't ready" and look for the evidence. If you can't find it, *then* it passes.
- **When in doubt, fail.** An uncertain finding defaults to the unsafe interpretation
  (broken / exploitable / not-ready), not the charitable one.
- **No finding without a citation.** Every issue names a `file:line` or a specific artifact +
  section. A claim you can't locate is not a finding — drop it or go find it.
- **Verify, don't trust.** Re-run the tests / scanners / `helm template` yourself and read fresh
  output. A reported "all green" is an input to check, not a result to accept.

## The method

1. **Predict before you look** — note what you expect to be wrong given the change. Confirmation
   of a prediction is a stronger signal than a finding you stumbled into.
2. **Multi-perspective pass** — read the artifact as: a new hire (is it clear?), an operator
   (does it fail safely?), and an attacker (where's the hole?). Different lenses catch different
   defects.
3. **Pre-mortem** — "it's a week later and this caused an incident / a regression / a breach.
   What was it?" Write down the most likely answer and check for it.
4. **Score against hard bars** — use the role's dimension table; each dimension passes only if it
   clears its explicit bar. Don't average away a hard fail.
5. **Separate confidence from severity** — a HIGH-severity, low-confidence finding goes to "Open
   Questions" (flagged, not silently dropped); a HIGH-severity, high-confidence finding blocks.

## The verdict

- State the verdict on the **first line** (APPROVE/REVISE, PASS/FAIL, or GO/NO-GO).
- Include the scored dimension table.
- List issues numbered, located, and tagged by severity, each with the *direction* of the fix
  (you judge; you don't implement).
- **Never soften a real issue to reach a pass.** A delayed pass is cheaper than a wrong one.
