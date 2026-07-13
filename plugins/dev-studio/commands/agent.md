---
description: Dispatch one dev-studio role directly — /dev-studio:agent <role> <task> delegates the task to that specialist (planner|engineer|reviewer|operator|e2e-tester|marketer|coordinator), skipping the workflow gates
argument-hint: "<role> <task>  e.g. 'marketer 为 orders 服务做市场评估'"
allowed-tools: Task, Read, Glob, Grep, AskUserQuestion
---

# Direct role dispatch

Delegate a single task to one dev-studio specialist, bypassing the workflow
orchestration. The first word of the arguments is the role; the rest is the task.

Arguments: `$ARGUMENTS`

1. **Parse the role.** The first token (with any leading `@` stripped) must be one
   of: `planner`, `engineer`, `reviewer`, `operator`, `e2e-tester`, `marketer`,
   `coordinator`. If it isn't, list the valid roles and stop.
2. **Frame the prompt.** Everything after the role token is the task. Add any
   obviously relevant session context (service name, contract path under
   `./out/`, live URLs). For `e2e-tester`, the product URL, API URL, and Grafana
   URL are required — ask for missing ones before delegating.
3. **Delegate once** via the Task tool to subagent type `dev-studio:<role>` —
   one level only; do not chain further roles yourself.
4. **Report the result** and, in one line, note the gate this shortcut skipped
   (e.g. marketer output normally passes the reviewer's fabrication/accuracy
   gate; engineer output normally passes the reviewer's PASS/FAIL gate). Suggest
   the matching `/dev-studio:workflows:*` command when the task clearly wants
   the full loop.

Guardrails still apply: the role writes only its own surface (`src/` for
builders, verdict files for judges), nothing is applied or published live, and
verdicts from judges are reported as-is — never softened.
