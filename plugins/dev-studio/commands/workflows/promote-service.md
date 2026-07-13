---
description: Go-to-market for a shipped product — a promo deck (via aws300/slides, ppt-master fallback) + a search-driven market assessment, challenged for fabrication/accuracy. GO/NO-GO.
argument-hint: "[the product to promote, e.g. 'orders API']"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Task, AskUserQuestion, WebSearch, WebFetch
model: sonnet
---

# Promote Service (local surface)

Run the `promote-service` workflow interactively, for a product that has shipped (ideally passed
acceptance).

If no product is given, ask "Which shipped product should we promote?" and stop.

Load `agents/workflows/promote-service.md` for the contract, then delegate with `Task`
— **one level only**: `marketer` (promo deck — **prefer `git@github.com:aws300/slides.git`**, fall
back to ppt-master only for a required pptx; plus a cited `market-assessment.md` with comparable
products + recommended directions, all under `src/marketing/`) → `reviewer` (challenges for
fabricated/unsourced claims and accuracy vs. what shipped — **GO/NO-GO**) → package to `./out/`.

Use `AskUserQuestion` to approve before packaging. A NO-GO loops back to the marketer. Never market
a feature that didn't ship; never assert a market claim without a citation. Cloning/pulling the
slides repo and running its local build are fine; **publishing/pushing the deck is a human action**
— staged for sign-off, never autonomous.
