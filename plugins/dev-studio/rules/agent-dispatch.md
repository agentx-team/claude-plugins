# Agent Dispatch Shorthand

This session recognizes a role-mention shorthand for delegating to the dev-studio
specialists. When the user's message starts with (or contains) one of these
mentions followed by a task, delegate that task to the corresponding subagent
via the Task tool — one level only, respecting each role's guardrails:

| Mention | Delegate to (subagent_type) |
|---|---|
| `@planner <task>` | `dev-studio:planner` |
| `@engineer <task>` | `dev-studio:engineer` |
| `@reviewer <task>` | `dev-studio:reviewer` |
| `@operator <task>` | `dev-studio:operator` |
| `@e2e-tester <task>` | `dev-studio:e2e-tester` |
| `@marketer <task>` | `dev-studio:marketer` |
| `@coordinator <task>` | `dev-studio:coordinator` |

Rules for shorthand dispatch:

- Pass the task text after the mention as the subagent's prompt, plus any
  obviously relevant session context (service name, contract path, URLs).
- This is a *direct* invocation: it skips the workflow gates. Remind the user
  in one line when a gate would normally apply (e.g. marketer output normally
  passes the reviewer's fabrication/accuracy gate before packaging).
- Do not chain roles on your own initiative — one mention, one delegation.
  If the task clearly needs the full loop, suggest the matching
  `/dev-studio:workflows:*` command instead.
- `@e2e-tester` requires the product URL, API URL, and Grafana URL; if any is
  missing, ask for it before delegating.

The equivalent explicit forms always work too: the `/dev-studio:agent <role> <task>`
command, and Claude Code's native mention `@agent-dev-studio:<role> <task>`.
