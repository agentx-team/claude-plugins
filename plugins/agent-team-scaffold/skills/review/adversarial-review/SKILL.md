---
name: adversarial-review
description: Adversarially evaluate an output (a plan or a build) to find failures, not confirm success. Use when issuing a PASS/FAIL or APPROVE/REVISE verdict with scored dimensions. Triggers on "evaluate", "review for failures", "challenge this", "issue a verdict", "find what's broken".
---

# Adversarial Review

The method for the Evaluator and Design Evaluator. The goal is to **find
failures**, not to be agreeable.

## Why this skill exists

LLMs grade their own and each other's work leniently. The single biggest lift in
multi-agent output quality comes from a *separate* agent tuned to be skeptical.
Out of the box a model finds a real issue, then rationalizes it away — this skill
is the discipline that prevents that.

## The discipline

1. **Read primary sources.** Never grade off the producer's summary — open the
   actual artifact and the contract.
2. **Skip the happy path.** The producer already tested it. You test what they
   skipped: empty/null inputs, extremes, error states, transitions, missing
   references, off-by-one. For interactive output, walk the whole flow.
3. **Score concrete dimensions, not "is this good?"** Pick 3–5 dimensions that
   turn the subjective question into gradable terms; give each a 0.0–1.0 score
   and a hard threshold. Any dimension below threshold = FAIL/REVISE.
4. **File every divergence.** Filing a borderline issue is cheap; approving a
   hidden defect is expensive. When in doubt, fail.
5. **The "laziest passing output" test.** Ask: what is the minimal output that
   technically satisfies every criterion? If that would be unacceptable, the
   criteria are too weak — say so.

## Anti-leniency self-check before you submit

- Did I mark any issue "advisory" without justifying why it isn't blocking?
- Did I pass any criterion based on the producer's claim rather than my own check?
- Is my verdict PASS/APPROVE with zero substantive critiques? If so, look again —
  that usually means I wasn't skeptical enough.

## Verdict

End with a scored table + blocking issues + advisory notes + an overall
**PASS/FAIL** (builds) or **APPROVE/REVISE** (plans). A FAIL/REVISE loops back to
the producer against the same contract — never forward.
