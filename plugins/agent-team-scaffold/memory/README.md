# Memory Taxonomy & Seeds

Every durable memory this team writes is one of **four types**. The type decides
who may write it, when it is consulted, and how it is retired — untyped memory
rots into noise.

| Type | What it captures | Litmus test | Write discipline | Lifecycle |
|---|---|---|---|---|
| **Fact** | Verifiable state of the world/project: stack, endpoints, decisions made, glossary | "Could a script check this?" | Anyone (in a `read_write` store); one fact per entry, with its source | Update in place when the world changes; a stale fact is worse than none |
| **Rule** | Binding constraint on behavior: must / never | "Does violating it fail a review?" | **Human sign-off only** — agents propose, never enact | Changes are versioned; conflicts resolve to the newer rule, loudly |
| **Learned** | Distilled experience: a pattern that worked or failed, with the evidence | "Would this change how I act next time?" | The agent that lived it, right after the verdict/outcome | Revisable; periodically consolidated (dreams) — merge duplicates, drop superseded |
| **Warning** | A known pitfall with its **trigger**: "if you see X, expect Y" | "Is there a concrete trigger condition?" | The agent that hit the pitfall, or the coordinator after a dispute | Retire when the root cause is fixed — expired warnings breed alert fatigue |

## Entry format

One entry = one tagged block. Keep entries small and focused (CMA limit: a
memory ≤ 100 kB, but the useful size is 3–10 lines):

```
[FACT] <one-line statement>
source: <where this was established — file, decision, measurement>

[RULE] <must/never statement>
owner: <who signed it off> · since: <version/date>

[LEARNED] <the pattern, one line>
evidence: <the sprint/verdict where it showed up>
apply: <what to do differently next time>

[WARNING] <the pitfall, one line>
trigger: <the concrete condition that should raise it>
then: <what to check before proceeding>
```

## Which store holds which types

| Store (see `scripts/cma/cma.yaml`) | Types it holds | Why |
|---|---|---|
| `team-standards` (agent-scope, **read-only**) | Rule + Fact | The org bar: binding rules and stable org facts. Read-only ⇒ agents can never relax a rule mid-sprint. |
| `project-context` (project-scope, read-write) | Fact + Learned | What this project knows: its decisions (facts) and its accumulated experience. |
| `evaluator-calibration` (agent-scope, read-write, evaluator-private) | Learned + Warning | The judge's professional memory: leniency patterns it keeps missing, and triggers that demand extra skepticism. |
| `session-scratch` (session-scope) | — none | Scratch is not memory. Anything worth keeping is re-filed into a typed store before session end. |

The seed files in this directory are uploaded into the stores at deploy time
(`cma-deploy` / `scripts/cma/deploy.py`; each store's `seed:` in `cma.yaml`
points here). Locally the same files serve as the worked examples the roles'
`memory: project` habit should imitate.

**Filing rules of thumb**

- Can't decide between Fact and Learned? If it's about *the world*, it's a Fact;
  if it's about *how to act*, it's Learned.
- A Learned entry that starts being cited as "must" is a Rule candidate —
  escalate it to the coordinator for human sign-off; don't quietly treat it as one.
- A Warning without a trigger is a vibe, not a warning — rewrite or drop it.
