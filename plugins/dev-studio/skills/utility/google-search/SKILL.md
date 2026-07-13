---
name: google-search
description: |
  Perform Google searches via CDP connection to the existing Chrome browser at localhost:9222.
  Use this skill whenever the user wants to search Google for any information: web pages, news articles,
  images, videos, site-specific content, or needs advanced search operators (filetype, time filter,
  exact phrase, exclude terms, etc.).
  Trigger on: "search for X", "find news about X", "look up X on Google", "search github for X",
  "find recent articles about X", "google X", "research X", "find PDF about X", "what does Google say about X",
  "search the web for X", "find images of X", "search site:Y for X".
  Requires the playwright-cli skill for direct browser commands (tab management, snapshots, eval).
requires: playwright-cli
allowed-tools: Bash(python3:*) Bash(python:*) Bash(playwright-cli:*) Bash(curl:*)
---

# Google Search Skill

Connects to Chrome at `http://localhost:9222` via CDP (no new browser launched).

> **Requires**: [`playwright-cli` skill](../playwright-cli/SKILL.md) — load it for all direct
> browser commands (`playwright-cli open/goto/snapshot/eval/tab-*`). The Python scripts
> (`google_search.py`) work standalone without it.

## Scripts

All scripts live in `scripts/` relative to this SKILL.md.

| Script | Purpose |
|--------|---------|
| `google_search.py` | Main search CLI — structured JSON results |
| `search_utils.py` | URL builder, CAPTCHA detector, JS extractors (imported by main script) |

## Quick Start

```bash
SKILL_DIR="/home/core/Workspace/skills/google-search"

# Basic web search
python3 $SKILL_DIR/scripts/google_search.py --query "YOUR QUERY" --limit 10

# News from past week
python3 $SKILL_DIR/scripts/google_search.py --query "AI news" --type news --time w

# Site-specific search
python3 $SKILL_DIR/scripts/google_search.py --query "async await" --site stackoverflow.com

# Get raw HTML
python3 $SKILL_DIR/scripts/google_search.py --query "YOUR QUERY" --html
```

## All Options

```
--query,   -q   (required) Search terms
--type,    -t   web | news | images | videos | shopping   [default: web]
--limit,   -n   Max results 1-50                          [default: 10]
--lang,    -l   Language code: en, ja, zh, ko, de, fr...
--region,  -r   Country code: us, jp, cn, kr, gb, de...
--time         Time filter: h|d|w|m|y (hour/day/week/month/year)
--site,    -s   Restrict to domain e.g. github.com
--filetype     File type: pdf | doc | xls | ppt
--safe         off | medium | high                        [default: off]
--exact        Exact phrase to match (auto-quoted)
--exclude      Comma-separated terms to exclude
--html         Return cleaned page HTML instead of structured results
--output,  -o  Write JSON to file instead of stdout
--cdp          CDP endpoint                               [default: http://localhost:9222]
--timeout      Navigation timeout ms                      [default: 30000]
```

## Search Type Examples

```bash
SCRIPT="python3 /home/core/Workspace/skills/google-search/scripts/google_search.py"

# Web search (default)
$SCRIPT --query "playwright testing best practices"

# News — recent articles
$SCRIPT --query "OpenAI GPT-5" --type news --time d

# Images
$SCRIPT --query "golden gate bridge" --type images --limit 15

# Videos
$SCRIPT --query "playwright tutorial" --type videos

# Shopping
$SCRIPT --query "mechanical keyboard" --type shopping --region us

# Site-specific (site: operator)
$SCRIPT --query "react hooks" --site github.com
$SCRIPT --query "async await" --site stackoverflow.com

# File type
$SCRIPT --query "machine learning introduction" --filetype pdf

# Exact phrase
$SCRIPT --query "tutorial" --exact "transformer architecture"

# Time filtered
$SCRIPT --query "typescript news" --time w        # past week
$SCRIPT --query "AI breaking news" --time d       # past 24h
$SCRIPT --query "annual report" --time y          # past year

# Exclude terms
$SCRIPT --query "python tutorial" --exclude "beginner,snake,biology"

# Language + region
$SCRIPT --query "latest tech news" --lang en --region us
$SCRIPT --query "recent AI news" --lang ja --region jp

# Combined operators
$SCRIPT --query "AI research" --site arxiv.org --filetype pdf --time m
$SCRIPT --query "bug report" --site github.com --time w --limit 5
```

## Output Format

### Web / News results
```json
{
  "query": "playwright testing",
  "search_url": "https://www.google.com/search?q=...",
  "type": "web",
  "result_count": 10,
  "results": [
    {
      "title": "Playwright: Fast and reliable end-to-end testing",
      "url": "https://playwright.dev/",
      "snippet": "Enables reliable web automation for testing..."
    }
  ]
}
```

### News results (additional fields)
```json
{
  "title": "...",
  "url": "...",
  "source": "The Verge",
  "snippet": "...",
  "time": "2 hours ago"
}
```

### Image results
```json
{
  "src": "https://...",
  "alt": "image description",
  "title": ""
}
```

## CAPTCHA Handling

If Google detects automation, the script **does NOT exit immediately**. Instead it:

1. Leaves the browser tab **open** (never closes it — session cookies are precious)
2. Polls the page URL every 3 seconds for up to 2 minutes
3. If the human completes verification, automatically continues the search
4. If the 2-minute timeout expires, exits with **code 2** — tab stays open

**When CAPTCHA occurs — do NOT close the browser.**

```bash
# Check exit code
$SCRIPT --query "your query"
echo "Exit code: $?"   # 0=success, 1=error, 2=CAPTCHA timeout

# Script waits automatically — just open the browser and verify:
# http://localhost:9222
# Complete the CAPTCHA, then the script resumes on its own.
# Only if it times out (2 min): re-run after verifying.
```

Tell the user when CAPTCHA is detected:
```
⚠️  CAPTCHA detected. The browser tab at http://localhost:9222 is being kept open.
Please open the browser, complete the CAPTCHA on the "Unusual Traffic" tab.
The script is polling and will continue automatically once you pass — DO NOT close the browser.
```

## Reference Files

- [references/search-operators.md](references/search-operators.md) — All search operators, URL params, language/region codes
- [references/captcha-handling.md](references/captcha-handling.md) — CAPTCHA detection, human resolution steps, retry patterns
