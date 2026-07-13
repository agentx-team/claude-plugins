#!/usr/bin/env python3
"""
Google Search Script
Python port of google-search-mcp/src/search.ts

Connects to an existing Chrome browser via CDP at localhost:9222,
performs Google searches, extracts results, and handles CAPTCHA gracefully.

Usage:
    python google_search.py --query "playwright testing" --limit 10
    python google_search.py --query "AI news" --type news --time w --limit 5
    python google_search.py --query "react hooks" --site github.com
    python google_search.py --query "ML paper" --filetype pdf

Output: JSON to stdout, status/errors to stderr.
Exit codes: 0=success, 1=error, 2=CAPTCHA detected
"""

import argparse
import json
import sys
import time
import os
from typing import Optional

from playwright.sync_api import sync_playwright, Browser, BrowserContext, Page

# Allow importing from the same directory
sys.path.insert(0, os.path.dirname(__file__))
from search_utils import (
    build_search_url,
    is_captcha_url,
    EXTRACT_WEB_RESULTS_JS,
    EXTRACT_NEWS_RESULTS_JS,
    EXTRACT_IMAGE_RESULTS_JS,
)

CDP_ENDPOINT = os.environ.get("CDP_ENDPOINT", "http://localhost:9222")
CAPTCHA_WAIT_TIMEOUT = 120_000   # ms — 2 minutes for human CAPTCHA completion

# Set to True when we intentionally leave a CAPTCHA tab open so the finally
# block knows NOT to close the page.
_captcha_tab_open = False


def connect_browser(playwright, retries: int = 3) -> Browser:
    """
    Connect to existing Chrome via CDP with retry logic.
    Mirrors BrowserManager.doConnect() from search.ts.
    """
    endpoint = os.environ.get("CDP_ENDPOINT", CDP_ENDPOINT)
    last_err = None
    for attempt in range(1, retries + 1):
        try:
            browser = playwright.chromium.connect_over_cdp(endpoint, timeout=30_000)
            label = f" (attempt {attempt})" if attempt > 1 else ""
            print(f"[google-search] CDP connected to {endpoint}{label}", file=sys.stderr)
            return browser
        except Exception as e:
            last_err = e
            print(f"[google-search] CDP attempt {attempt}/{retries} failed: {e}", file=sys.stderr)
            if attempt < retries:
                time.sleep(2 * attempt)
    raise RuntimeError(f"CDP connection failed after {retries} attempts: {last_err}")


def wait_for_captcha_resolution(page: Page, captcha_url: str) -> bool:
    """
    Detect CAPTCHA and WAIT — the browser tab stays open until the human
    completes verification or the 2-minute timeout expires.

    Returns True if CAPTCHA was resolved (page navigated away from sorry URL).
    Returns False on timeout — caller should treat search as failed.

    Critical: this function NEVER closes the page / browser.
    """
    global _captcha_tab_open
    _captcha_tab_open = True

    print(f"\n{'='*60}", file=sys.stderr)
    print("⚠️  CAPTCHA / Bot Detection", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    print(f"URL: {captcha_url}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Please open the browser and complete verification:", file=sys.stderr)
    print(f"  CDP browser: {CDP_ENDPOINT}", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"Waiting up to {CAPTCHA_WAIT_TIMEOUT // 1000}s for you to verify...", file=sys.stderr)
    print("DO NOT close the browser — session cookies are needed.", file=sys.stderr)
    print(f"{'='*60}\n", file=sys.stderr)

    # Also emit JSON so the calling agent can surface it to the user
    captcha_info = {
        "captcha": True,
        "captcha_url": captcha_url,
        "message": (
            f"CAPTCHA detected. Please open the browser at {CDP_ENDPOINT}, "
            "complete the verification on the Google tab, then wait — the script "
            "will automatically continue once you pass."
        ),
        "instructions": [
            f"1. Open browser at {CDP_ENDPOINT}",
            "2. Find the tab showing the Google 'Unusual Traffic' / CAPTCHA page",
            "3. Complete the verification (checkbox / image puzzle)",
            "4. The script will detect the redirect and continue automatically",
            "   — DO NOT close the browser or this terminal",
        ],
        "waiting_seconds": CAPTCHA_WAIT_TIMEOUT // 1000,
    }
    print(json.dumps(captcha_info, ensure_ascii=False, indent=2), file=sys.stderr)

    # Poll until the page leaves the CAPTCHA URL or we time out
    poll_interval = 3   # seconds
    waited = 0
    max_wait = CAPTCHA_WAIT_TIMEOUT // 1000

    while waited < max_wait:
        time.sleep(poll_interval)
        waited += poll_interval
        try:
            current_url = page.url
        except Exception:
            # Page may have been closed externally
            break
        if not is_captcha_url(current_url):
            print(f"[google-search] CAPTCHA resolved after {waited}s ✓", file=sys.stderr)
            _captcha_tab_open = False
            return True
        remaining = max_wait - waited
        print(f"[google-search] Still waiting for CAPTCHA... ({remaining}s remaining)", file=sys.stderr)

    # Timed out — leave the tab open, exit with code 2 so the agent can inform
    # the user and ask them to re-run after verifying manually.
    print("[google-search] CAPTCHA wait timed out. Browser tab left open.", file=sys.stderr)
    timeout_info = {
        "captcha": True,
        "timed_out": True,
        "message": (
            "CAPTCHA verification timed out. The browser tab has been left open. "
            "Please complete the verification manually and re-run the search."
        ),
    }
    print(json.dumps(timeout_info, ensure_ascii=False, indent=2))
    sys.exit(2)


def extract_results(page: Page, search_type: str, limit: int) -> list:
    """
    Extract search results from current page based on search type.
    Mirrors extractSearchResults() from search.ts.
    """
    if search_type in ("images", "isch"):
        return page.evaluate(EXTRACT_IMAGE_RESULTS_JS, limit)
    elif search_type in ("news", "nws"):
        return page.evaluate(EXTRACT_NEWS_RESULTS_JS, limit)
    else:
        return page.evaluate(EXTRACT_WEB_RESULTS_JS, limit)


def perform_search(
    query: str,
    search_type: str = "web",
    limit: int = 10,
    language: Optional[str] = None,
    region: Optional[str] = None,
    time_range: Optional[str] = None,
    site: Optional[str] = None,
    filetype: Optional[str] = None,
    safe: str = "off",
    exact_phrase: Optional[str] = None,
    exclude_terms: Optional[list] = None,
    timeout: int = 30_000,
) -> dict:
    """
    Full search workflow: connect → navigate → check CAPTCHA → extract results.
    Mirrors googleSearch() from search.ts.
    """
    search_url = build_search_url(
        query=query,
        search_type=search_type,
        time_range=time_range,
        language=language,
        region=region,
        safe=safe,
        site=site,
        filetype=filetype,
        exact_phrase=exact_phrase,
        exclude_terms=exclude_terms,
    )

    print(f"[google-search] Searching: {search_url}", file=sys.stderr)

    with sync_playwright() as playwright:
        browser = connect_browser(playwright)
        context: BrowserContext = browser.contexts[0]
        if not context:
            raise RuntimeError("No browser context. Is Chrome running?")

        page: Page = context.new_page()
        try:
            page.goto(search_url, timeout=timeout, wait_until="networkidle")

            # First CAPTCHA check — wait for human to resolve before continuing
            if is_captcha_url(page.url):
                resolved = wait_for_captcha_resolution(page, page.url)
                if not resolved:
                    # wait_for_captcha_resolution already called sys.exit(2) on timeout
                    return {}
                # Resolved — navigate to the original search URL
                page.goto(search_url, timeout=timeout, wait_until="networkidle")

            # Wait for results container
            result_selectors = ["#search", "#rso", ".g", ".WlydOe", "article"]
            for sel in result_selectors:
                try:
                    page.wait_for_selector(sel, timeout=timeout // 2)
                    break
                except Exception:
                    pass

            # Second CAPTCHA check after waiting
            if is_captcha_url(page.url):
                resolved = wait_for_captcha_resolution(page, page.url)
                if not resolved:
                    return {}
                page.goto(search_url, timeout=timeout, wait_until="networkidle")

            # Small settle delay for dynamic content
            page.wait_for_timeout(500)

            results = extract_results(page, search_type, limit)
            print(f"[google-search] Found {len(results)} results", file=sys.stderr)

            return {
                "query": query,
                "search_url": search_url,
                "type": search_type,
                "result_count": len(results),
                "results": results,
            }

        finally:
            # Only close the page if we are NOT leaving a CAPTCHA tab open.
            # If a CAPTCHA was detected and timed out, the tab must stay alive
            # so the user can complete verification with the session intact.
            if not _captcha_tab_open:
                page.close()
            # Disconnect only — never close the browser process itself
            browser.close()


def get_page_html(
    query: str,
    search_type: str = "web",
    language: Optional[str] = None,
    region: Optional[str] = None,
    time_range: Optional[str] = None,
    site: Optional[str] = None,
    timeout: int = 30_000,
) -> dict:
    """
    Get cleaned HTML of Google search results page.
    Mirrors getGoogleSearchPageHtml() from search.ts.
    """
    import re

    search_url = build_search_url(
        query=query,
        search_type=search_type,
        time_range=time_range,
        language=language,
        region=region,
        site=site,
    )

    print(f"[google-search] Getting HTML: {search_url}", file=sys.stderr)

    with sync_playwright() as playwright:
        browser = connect_browser(playwright)
        context: BrowserContext = browser.contexts[0]
        page: Page = context.new_page()
        try:
            page.goto(search_url, timeout=timeout, wait_until="networkidle")

            if is_captcha_url(page.url):
                resolved = wait_for_captcha_resolution(page, page.url)
                if not resolved:
                    return {}
                page.goto(search_url, timeout=timeout, wait_until="networkidle")

            page.wait_for_timeout(1000)
            page.wait_for_load_state("networkidle", timeout=timeout)

            full_html = page.content()
            # Strip style and script tags (mirror MCP server behaviour)
            html = re.sub(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>', '', full_html, flags=re.IGNORECASE)
            html = re.sub(r'<link\s+[^>]*rel=["\']stylesheet["\'][^>]*>', '', html, flags=re.IGNORECASE)
            html = re.sub(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', '', html, flags=re.IGNORECASE | re.DOTALL)

            print(f"[google-search] HTML size: {len(full_html)} -> {len(html)} (cleaned)", file=sys.stderr)

            return {
                "query": query,
                "search_url": search_url,
                "url": page.url,
                "html_length": len(html),
                "original_html_length": len(full_html),
                "html": html,
            }

        finally:
            if not _captcha_tab_open:
                page.close()
            browser.close()


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Google Search via CDP browser connection",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python google_search.py --query "playwright testing" --limit 10
  python google_search.py --query "AI news" --type news --time w
  python google_search.py --query "react hooks" --site github.com
  python google_search.py --query "ML paper" --filetype pdf
  python google_search.py --query "hello world" --type images --limit 15
  python google_search.py --query "python tutorial" --exclude "beginner,snake"
  python google_search.py --query "tutorial" --exact "deep learning" --lang en --region us
  python google_search.py --query "report" --html --output page.html
        """
    )
    parser.add_argument("--query", "-q", required=True, help="Search query")
    parser.add_argument("--type", "-t", default="web",
                        choices=["web", "news", "images", "videos", "shopping"],
                        help="Search type (default: web)")
    parser.add_argument("--limit", "-n", type=int, default=10,
                        help="Max results (default: 10)")
    parser.add_argument("--lang", "-l", help="Language code e.g. en, ja, zh")
    parser.add_argument("--region", "-r", help="Country code e.g. us, jp, cn")
    parser.add_argument("--time", help="Time filter: h|d|w|m|y (hour/day/week/month/year)")
    parser.add_argument("--site", "-s", help="Restrict to domain e.g. github.com")
    parser.add_argument("--filetype", help="File type e.g. pdf, doc")
    parser.add_argument("--safe", default="off", choices=["off", "medium", "high"],
                        help="Safe search level")
    parser.add_argument("--exact", help="Exact phrase to match (will be quoted)")
    parser.add_argument("--exclude", help="Comma-separated terms to exclude")
    parser.add_argument("--html", action="store_true",
                        help="Get raw HTML instead of structured results")
    parser.add_argument("--output", "-o", help="Write output to file (default: stdout)")
    parser.add_argument("--cdp", default=CDP_ENDPOINT,
                        help=f"CDP endpoint (default: {CDP_ENDPOINT})")
    parser.add_argument("--timeout", type=int, default=30000,
                        help="Navigation timeout in ms (default: 30000)")

    args = parser.parse_args()

    # Allow overriding CDP endpoint via flag
    os.environ["CDP_ENDPOINT"] = args.cdp

    exclude_list = [t.strip() for t in args.exclude.split(",")] if args.exclude else None

    try:
        if args.html:
            result = get_page_html(
                query=args.query,
                search_type=args.type,
                language=args.lang,
                region=args.region,
                time_range=args.time,
                site=args.site,
                timeout=args.timeout,
            )
        else:
            result = perform_search(
                query=args.query,
                search_type=args.type,
                limit=args.limit,
                language=args.lang,
                region=args.region,
                time_range=args.time,
                site=args.site,
                filetype=args.filetype,
                safe=args.safe,
                exact_phrase=args.exact,
                exclude_terms=exclude_list,
                timeout=args.timeout,
            )

        output = json.dumps(result, ensure_ascii=False, indent=2)

        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(output)
            print(f"[google-search] Output written to {args.output}", file=sys.stderr)
        else:
            print(output)

    except SystemExit:
        raise  # Re-raise exit codes (e.g., CAPTCHA exit code 2)
    except Exception as e:
        error = {"error": str(e), "query": args.query}
        if "connect" in str(e).lower() or "cdp" in str(e).lower():
            error["hint"] = f"Make sure Chrome is running with --remote-debugging-port=9222 (CDP at {CDP_ENDPOINT})"
        print(json.dumps(error, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
