# Coordination Rules — dev-studio

The binding invariants for the Build → Ship → Accept → Promote lifecycle. These are
non-negotiable; the coordinator enforces them.

## 1. Producer ≠ judge
The agent that generates is never the agent that judges. The `engineer` / `operator` / `marketer`
build; the `reviewer` and `e2e-tester` challenge. A Generator never self-certifies, and a judge
never approves work it authored elsewhere. This separation is the single biggest quality lever —
protect it.

## 2. The acceptance judge is black-box
`e2e-tester` runs under the `tester` role with **no repository file tools** — only `websearch` /
`webfetch`. It is given the product URL, API URL, and Grafana URL, and **must never see source**.
It argues only from observable behavior; if a finding needs the code to explain, it is restated as
an observable defect or the dimension fails. This is both a quality guarantee (real black-box
acceptance) and a security boundary (the acceptance judge can't leak or be biased by internals).

## 3. Marketing never outruns the product
The `marketer` may only claim capabilities that actually shipped (grounded in `./out/<service>/` +
the contract) and may only assert market claims that are **cited**. The `reviewer` gates the promo
package for fabrication and accuracy; a fabricated feature or an unsourced statistic is a NO-GO.
Publishing/pushing a deck is a human action, never autonomous.

## 4. Verdicts are binding
- Plan **REVISE** → back to the planner; the build does not start until APPROVE.
- Build **FAIL** → back to the engineer; nothing packages until PASS.
- Release **NO-GO** → back to the operator; nothing packages until GO.
- Acceptance **FAIL** → UI/API/log gaps to the engineer, observability gaps to the operator; the
  service is not accepted until PASS.
- Promote **NO-GO** → back to the marketer; nothing packages until GO.
- An ignored verdict is the worst failure mode. The coordinator ensures every verdict loops back.

## 5. The reviewer (and tester) stay skeptical
LLMs grade their own output leniently and drift toward PASS over a long session. Every judge's
mandate is to **find failures**; when in doubt, FAIL. The coordinator watches for leniency drift
(passes with shrinking justification, criteria VERIFIED with no fresh test output, security PASS
with no scan run, an acceptance PASS where the tester never generated load or opened Grafana, a
promo claim accepted without a citation) and re-tightens the bar.

## 6. One writer per surface
- `engineer` / `operator` / `marketer` write only `src/` (the marketer only `src/marketing/`).
- `reviewer` is read-only (writes only its verdict file); `e2e-tester` writes nothing (returns its
  verdict as its final message).
- `packager` (resolver) writes only `./out/`, and only after the binding verdicts pass.
No two agents write the same file; sequence conflicting work through one Generator pass.

## 7. One-level delegation
The workflow orchestrator delegates to depth-1 leaves only; leaves never nest
(`callable_agents: []`, enforced by `build.py`). Keep the topology flat.

## 8. The repo is the process spec
The agents follow the scaffold repo's own scripts and CI (`CONTRIBUTING.md`, `protos/Makefile`,
`scripts/deploy.sh`, `.github/workflows/`, `charts/`) — they don't re-explain or fork the process.
Proto-first always; generated code is never hand-edited. Reuse the existing platform and data
services; adding infrastructure is a last resort.

## 9. Nothing is applied or published live
All deploys, pushes, cluster mutations, and deck publishing are staged for a human operator —
never executed by an agent (also enforced in `.claude/settings.json` deny + the `validate-push`
hook). The model is parameterized in `cma.yaml`.
