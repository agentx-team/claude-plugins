# CAPTCHA / Bot Detection Handling

## Overview

Google occasionally detects automated browser usage and shows a verification page at:
- `google.com/sorry/...` — "Unusual traffic" page
- reCAPTCHA challenges

**Critical rule**: Never close the browser or end the playwright-cli session when a CAPTCHA appears. The session's cookies and browser fingerprint are what allows searches to succeed — closing loses them.

## Detection

The scripts detect CAPTCHA by checking the current page URL for these patterns:
- `google.com/sorry`
- `recaptcha`
- `captcha`
- `unusual traffic`

## What Happens When CAPTCHA Is Detected

### Behavior (updated)

The script **does NOT exit immediately** on CAPTCHA. It:

1. Prints a clear warning with instructions to stderr
2. **Keeps the browser tab open** — never calls `page.close()` while CAPTCHA is active
3. **Polls** `page.url` every 3 seconds for up to 2 minutes (`CAPTCHA_WAIT_TIMEOUT`)
4. If the human passes verification → page redirects away from the `sorry` URL → script **automatically continues** the search
5. If timeout expires → exits with **code 2**, tab remains open for manual recovery

### In `google_search.py`

On CAPTCHA detection, stderr shows:
```
============================================================
⚠️  CAPTCHA / Bot Detection
============================================================
URL: https://www.google.com/sorry/...

Please open the browser and complete verification:
  CDP browser: http://localhost:9222

Waiting up to 120s for you to verify...
DO NOT close the browser — session cookies are needed.
============================================================
[google-search] Still waiting for CAPTCHA... (117s remaining)
[google-search] Still waiting for CAPTCHA... (114s remaining)
...
[google-search] CAPTCHA resolved after 12s ✓       ← automatically continues
```

A JSON block is also printed to stderr so the calling agent can surface it:
```json
{
  "captcha": true,
  "captcha_url": "https://www.google.com/sorry/...",
  "message": "CAPTCHA detected. Please open the browser ...",
  "instructions": [...],
  "waiting_seconds": 120
}
```

On **timeout** (2 min with no resolution), stdout receives:
```json
{
  "captcha": true,
  "timed_out": true,
  "message": "CAPTCHA verification timed out. The browser tab has been left open. ..."
}
```
Exit code 2. Re-run after completing verification manually.

### In `playwright-cli` commands

After `playwright-cli goto <search-url>`, check the URL:
```bash
playwright-cli -s=google-search eval "page.url()"
```

If it contains `sorry` or `recaptcha`, tell the user:
```
⚠️  CAPTCHA detected on browser tab.
Current URL: [captcha url]

Please open http://localhost:9222 and complete the CAPTCHA verification.
DO NOT close the browser. Reply "continue" when done.
```

Then wait for user confirmation before retrying the `playwright-cli goto`.

## Human Resolution Steps

1. Open the browser display (webtop, or Chrome remote debug UI at `localhost:9222`)
2. Find the tab showing "Unusual Traffic" / CAPTCHA (URL contains `google.com/sorry`)
3. Complete the verification (checkbox, image selection, etc.)
4. The script detects the redirect automatically and resumes — no need to re-run
5. If the 2-minute timeout already expired, just re-run the script after verifying

## Agent Instructions (when to surface CAPTCHA to user)

When the script is running and CAPTCHA is detected, tell the user:

> ⚠️ Google CAPTCHA detected. The browser tab is being kept open at http://localhost:9222.
> Please open the browser, find the "Unusual Traffic" tab, and complete the verification.
> **The script will continue automatically once you pass** — DO NOT close the browser or the terminal.

Do **not** kill the process or close the browser tab while waiting.

## Prevention Tips

- Space out requests — don't run many searches in rapid succession
- The existing Chrome browser at localhost:9222 already has browsing history, which helps
- Use specific search queries rather than very generic ones
- Add `--lang en --region us` for consistent results (fewer locale redirects)

## Retry Pattern (if timeout expired)

```python
import subprocess

result = subprocess.run(
    ["python", "google_search.py", "--query", "your query"],
    capture_output=True, text=True
)

if result.returncode == 2:
    # Script already waited 2 min; tab is still open in browser
    print("CAPTCHA timed out — please complete verification in the browser, then press Enter")
    input()
    # Retry — session cookies should now be valid
    result = subprocess.run(
        ["python", "google_search.py", "--query", "your query"],
        capture_output=True, text=True
    )
```
