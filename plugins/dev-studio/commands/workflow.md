---
description: Run a dev-studio workflow by name — /dev-studio:workflow <name> <input> routes to deliver-service | ship-service | accept-service | promote-service (same as the /dev-studio:workflows:* commands)
argument-hint: "<workflow> <input>  e.g. 'deliver-service orders API: create + list orders'"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Task, AskUserQuestion
---

# Workflow dispatch by name

Generic dispatcher over the four lifecycle workflows — one argument form for all
of them, equivalent to the dedicated `/dev-studio:workflows:<name>` commands.

Arguments: `$ARGUMENTS`

1. **Parse the workflow.** The first token must be one of `deliver-service`,
   `ship-service`, `accept-service`, `promote-service` (accept the short forms
   `deliver`/`ship`/`accept`/`promote`). If it isn't, list the four workflows
   with one line each and stop.
2. **Load the matching command file** `commands/workflows/<workflow>.md` from
   this plugin and follow it exactly, treating the rest of the arguments as its
   input. Approval gates, delegation depth (one level), and packaging rules are
   defined there and in `agents/workflows/<workflow>.md`.
3. Do not skip gates: this is the *full* loop, unlike `/dev-studio:agent` which
   dispatches a single role directly.
