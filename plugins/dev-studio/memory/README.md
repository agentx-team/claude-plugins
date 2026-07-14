# Memory Taxonomy & Seeds

Every durable memory this studio writes is one of **four types**. The type
decides who may write it, when it is consulted, and how it is retired — untyped
memory rots into noise. (Same taxonomy as `agent-team-scaffold/memory/README.md`;
this file instantiates it for the delivery lifecycle.)

| Type | What it captures | Litmus test | Write discipline | Lifecycle |
|---|---|---|---|---|
| **Fact** | Verifiable state of the platform/project: stack, endpoints, decisions, glossary | "Could a script check this?" | Anyone (in a `read_write` store); one fact per entry, with its source | Update in place when the world changes; a stale fact is worse than none |
| **Rule** | Binding constraint on behavior: must / never | "Does violating it fail a review?" | **Human sign-off only** — agents propose via the coordinator, never enact | Changes are versioned; conflicts resolve to the newer rule, loudly |
| **Learned** | Distilled experience: a pattern that worked or failed, with the evidence | "Would this change how I act next time?" | The role that lived it, right after the verdict/outcome | Revisable; periodically consolidated (dreams) — merge duplicates, drop superseded |
| **Warning** | A known pitfall with its **trigger**: "if you see X, expect Y" | "Is there a concrete trigger condition?" | The role that hit the pitfall, or the coordinator after a dispute | Retire when the root cause is fixed — expired warnings breed alert fatigue |

## Entry format

One entry = one tagged block, 3–10 lines:

```
[FACT] <one-line statement>
source: <where this was established — file, decision, measurement>

[RULE] <must/never statement>
owner: <who signed it off> · since: <version/date>

[LEARNED] <the pattern, one line>
evidence: <the service/verdict where it showed up>
apply: <what to do differently next time>

[WARNING] <the pitfall, one line>
trigger: <the concrete condition that should raise it>
then: <what to check before proceeding>
```

## Which store holds which types

The studio has **two independent judges** (reviewer and the black-box
e2e-tester), so each gets its own private calibration store — a judge's
skepticism triggers must not be visible to the producers it judges, nor to the
other judge (their independence is the point).

| Store (see `scripts/cma/cma.yaml`) | Types | Mounted on | Why |
|---|---|---|---|
| `team-standards` (agent-scope, **read-only**) | Rule + Fact | every session | The studio bar: binding rules + stable platform facts. Read-only ⇒ nobody relaxes a rule mid-delivery. |
| `project-context` (project-scope, read-write) | Fact + Learned | every session | What this service/project knows: decisions and accumulated delivery experience. |
| `reviewer-calibration` (agent-scope, read-write) | Learned + Warning | reviewer only | The code/release/promo judge's professional memory across projects. |
| `e2e-calibration` (agent-scope, read-write) | Learned + Warning | e2e-tester only | The black-box judge's memory: flaky-signal patterns, observability blind spots. |
| `session-scratch` (session-scope) | — none | per workflow run | Scratch is not memory; re-file anything durable before session end. |

Seed files in `seeds/` are uploaded as each store's first memory at deploy time
(`cma.yaml` `seed:`; fulfilment mirrors `agent-team-scaffold/scripts/cma/deploy.py`
— wire it into `build.py --post`). Locally the same files are the worked
examples the roles' `memory: project` habit should imitate.

**Filing rules of thumb**

- About *the world* → Fact; about *how to act* → Learned.
- A Learned cited as "must" is a Rule candidate — escalate to the coordinator
  for human sign-off; don't quietly treat it as one.
- A Warning without a trigger is a vibe, not a warning — rewrite or drop it.
