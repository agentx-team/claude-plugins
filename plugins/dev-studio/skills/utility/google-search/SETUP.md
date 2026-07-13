# Google Search Skill — Setup Summary

## Overview

This document describes all configuration steps taken to install `playwright-cli`,
configure its global CDP default, and build the `google-search` skill on top of it.

---

## 1. Install `@playwright/cli`

`playwright-cli` (the old npm package) was deprecated. The replacement is `@playwright/cli`.

```bash
npm install -g @playwright/cli
playwright-cli --version   # 0.1.7
```

The binary `playwright-cli` is now available globally. It provides CLI-based browser
automation with session management, snapshots, tab control, and a `run-code` command
for executing arbitrary Playwright code.

---

## 2. Global CDP Default Configuration

**File**: `~/.playwright/cli.config.json`

```json
{
  "browser": {
    "cdpEndpoint": "http://localhost:9222",
    "cdpTimeout": 30000
  },
  "timeouts": {
    "action": 10000,
    "navigation": 60000
  },
  "outputMode": "stdout"
}
```

This file is the **global config** for `playwright-cli`. Source confirmation:
`playwright-core/lib/coreBundle.js:64954`:
```js
const globalConfigPath = path.join(os.homedir(), ".playwright", "cli.config.json");
```

With `cdpEndpoint` set, every `playwright-cli open` command automatically attaches
to the existing Chrome instance at `localhost:9222` instead of launching a new browser.
This preserves cookies, localStorage, and browser history across all sessions.

**Verify the config is applied:**
```bash
cd /home/core
playwright-cli open &
sleep 4
playwright-cli list   # browser-type should show "chrome"
playwright-cli close
```

---

## 3. Install playwright-cli Skills

The `playwright-cli install --skills` command installs the official skill files
into the `.claude/skills/playwright-cli/` directory of the current workspace.

```bash
# Install to home directory (for claude sessions started from ~)
cd /home/core && playwright-cli install --skills

# Install to Workspace (for claude sessions started from ~/Workspace)
cd /home/core/Workspace && playwright-cli install --skills
```

Installed locations:
- `/home/core/.claude/skills/playwright-cli/` — used when CWD is under `~/`
- `/home/core/Workspace/.claude/skills/playwright-cli/` — used when CWD is under `~/Workspace`

Each installation contains:
```
playwright-cli/
├── SKILL.md          # Core commands reference
└── references/       # Detailed guides (tests, mocking, sessions, storage, etc.)
```

---

## 4. Google Search Skill Structure

**Location**: `/home/core/Workspace/skills/google-search/`

```
google-search/
├── SKILL.md                    # Claude Code skill definition (trigger phrases, usage guide)
├── SETUP.md                    # This document
├── references/
│   ├── search-operators.md     # Google search operators and URL parameter reference
│   └── captcha-handling.md     # CAPTCHA detection and human-resolution workflow
└── scripts/
    ├── google_search.py        # Main search CLI — Python port of google-search-mcp/src/search.ts
    └── search_utils.py         # URL builder, CAPTCHA detector, DOM extraction JS strings
```

**Python dependency:**
```bash
pip install playwright==1.58.0
```

---

## 5. Python Scripts — Port of google-search-mcp

`google-search-mcp/src/search.ts` (TypeScript/Node.js) was ported to Python:

| TypeScript (MCP server)          | Python (skill script)                          |
|----------------------------------|------------------------------------------------|
| `BrowserManager.doConnect()`     | `connect_browser()` — CDP connect with retry   |
| `buildSearchUrl()`               | `build_search_url()` in `search_utils.py`      |
| `isBlockedUrl()`                 | `is_captcha_url()` in `search_utils.py`        |
| `waitForCaptchaVerification()`   | `wait_for_captcha_resolution()` — exit code 2  |
| `extractSearchResults()` (JS)    | `EXTRACT_WEB_RESULTS_JS` string constant       |
| `googleSearch()`                 | `perform_search()`                             |
| `getGoogleSearchPageHtml()`      | `get_page_html()`                              |

Key differences from the MCP server:
- **Sync API**: Uses `playwright.sync_api` instead of async (simpler for CLI use)
- **CAPTCHA exit**: Exits with code `2` immediately instead of blocking indefinitely
- **No auto-reconnect loop**: Retries CDP connection up to 3 times on startup only

---

## 6. Supported Search Types

| Flag           | Search Type     | URL Parameter       |
|----------------|-----------------|---------------------|
| `--type web`   | Web (default)   | *(none)*            |
| `--type news`  | News            | `tbm=nws`           |
| `--type images`| Images          | `tbm=isch`          |
| `--type videos`| Videos          | `tbm=vid`           |
| `--type shopping` | Shopping     | `tbm=shop`          |
| `--site d.com` | Site-restricted | `site:d.com` in `q` |
| `--filetype pdf` | File type     | `filetype:pdf` in `q` |
| `--exact "phrase"` | Exact phrase | `"phrase"` in `q`  |
| `--time d/w/m/y` | Time filter   | `tbs=qdr:d/w/m/y`  |
| `--exclude "a,b"` | Exclude terms | `-a -b` in `q`    |

---

## 7. CAPTCHA Handling

- Detection: checks page URL for `google.com/sorry`, `recaptcha`, `captcha`, `unusual traffic`
- On detection: **does not close the browser or session** — exits with code `2`
- Outputs a JSON block with `captcha: true` and resolution instructions to stdout
- Human opens `http://localhost:9222`, completes verification on the flagged tab, then re-runs the script
- See `references/captcha-handling.md` for the full workflow and retry patterns

---

## 8. Test Results

| Test Case                        | Result |
|----------------------------------|--------|
| Basic web search                 | PASS — correct results returned |
| News + time filter (past week)   | PASS — articles with source and relative time |
| Site-restricted (stackoverflow)  | PASS — 100% results from stackoverflow.com |
| File type (PDF)                  | PASS — `filetype:pdf` applied in query |
| Exact phrase match               | PASS — phrase wrapped in quotes in URL |
| Exclude terms                    | PASS — `-term` operators applied in query |

News DOM selectors were debugged via CDP inspection and updated from the generic
`article/[data-hveid]` approach to Google's actual class names:
- Container: `.SoaBEf` / Link: `.WlydOe` / Title: `.n0jPhd` / Time: `.OSrXXb`

---

## 9. Usage Examples

```bash
SCRIPT="python3 /home/core/Workspace/skills/google-search/scripts/google_search.py"

# Basic web search
$SCRIPT --query "playwright testing" --limit 10

# Latest news
$SCRIPT --query "AI developments" --type news --time w

# Search on GitHub
$SCRIPT --query "playwright cdp example" --site github.com

# Find PDF papers
$SCRIPT --query "deep learning paper" --filetype pdf

# Language and region targeting
$SCRIPT --query "latest tech news" --lang en --region us

# Save results to file
$SCRIPT --query "react hooks" --output results.json

# Get raw page HTML
$SCRIPT --query "openai" --html --output openai.html
```
