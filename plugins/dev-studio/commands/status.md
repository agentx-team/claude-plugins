---
description: Show the current state of the studio's Build → Ship → Accept → Promote lifecycle — active workflow/stage, last verdict, blockers, next action
argument-hint: ""
---

Load the `loop-status` skill and report the current state of the loop: the active workflow and
stage, the last verdict (APPROVE/REVISE, PASS/FAIL, or GO/NO-GO) with its score table, open
blocking issues with their `file:line` and owner, the single next action, and any `./out/`
packages awaiting human sign-off. Keep it a concise read-only status — do not start or modify work.
