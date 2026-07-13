---
name: promo-deck
description: Build a promotional deck for a shipped product — preferring the team slides system (git@github.com:aws300/slides.git), falling back to ppt-master (github.com/hugohe3/ppt-master) only when a .pptx is required. CEO-legible framing, grounded in real shipped capabilities. Use by the marketer. Triggers on "make slides", "promo deck", "pitch deck", "presentation", "pptx".
---

# Promo Deck

How to produce a promotional deck for a shipped product, using the team's tooling and a narrative
a non-technical decision-maker can follow.

## Tool preference (in order)

1. **Team slides system — `git@github.com:aws300/slides.git` (DEFAULT).** Clone/pull it, author
   the deck in its format (Slidev / aws-dark visual language), and follow its own build/deploy
   flow. Use this for essentially all promotion — it is the team standard and stays on-brand.
2. **`ppt-master` (github.com/hugohe3/ppt-master) — FALLBACK ONLY.** Reach for it only when a
   standalone `.pptx` file is specifically required and the slides system doesn't fit. Follow its
   own README for input → SVG → pptx export.

When unsure, use the slides system.

## Narrative (CEO-legible)

Lead with the outcome, not the implementation. A clean arc:

1. **Hook** — the problem / the stat that makes this matter.
2. **What it is** — one sentence a non-technical reader gets.
3. **Who it's for** — the target user and their pain.
4. **How it works** — the story at altitude (architecture only as much as a CEO needs).
5. **Why it's different** — the differentiation from the market assessment.
6. **Proof** — what shipped, what's measured (tie to the acceptance results if available).
7. **Call to action** — the next step.

Action titles ("Cuts onboarding from days to minutes"), not labels ("Onboarding"). One idea per
slide. Ground every claim in the shipped capabilities (read `./out/<service>/` + the contract) and
the cited market assessment.

## Output

The deck source under `src/marketing/` in the slides system's format (or the pptx + its source if
the fallback was used), plus a one-paragraph speaker summary.

## Guardrails

- You write only under `src/marketing/`. Cloning/pulling the slides repo and running its local
  build are fine; **publishing/pushing is staged for human sign-off** — never push autonomously.
- Never market a feature the product doesn't have. No fabricated metrics — cite or omit.
