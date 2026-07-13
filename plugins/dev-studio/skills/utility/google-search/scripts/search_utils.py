"""
Google Search Utilities
Port of google-search-mcp/src/search.ts utility functions to Python.

Provides URL building, CAPTCHA detection, and DOM extraction helpers.
"""

from urllib.parse import urlencode, quote_plus
from typing import Optional


GOOGLE_BASE = "https://www.google.com/search"

# Search type -> tbm parameter
SEARCH_TYPE_MAP = {
    "images": "isch",
    "news": "nws",
    "videos": "vid",
    "shopping": "shop",
    "web": None,  # default — no tbm
    "all": None,
}

# Time range -> tbs parameter
TIME_RANGE_MAP = {
    "h": "qdr:h",   # past hour
    "d": "qdr:d",   # past day
    "w": "qdr:w",   # past week
    "m": "qdr:m",   # past month
    "y": "qdr:y",   # past year
    "hour": "qdr:h",
    "day": "qdr:d",
    "week": "qdr:w",
    "month": "qdr:m",
    "year": "qdr:y",
}

# Safe search -> safe parameter
SAFE_MAP = {
    "off": "off",
    "medium": "medium",
    "high": "high",
}

CAPTCHA_PATTERNS = [
    "google.com/sorry",
    "recaptcha",
    "captcha",
    "unusual traffic",
]


def build_search_url(
    query: str,
    search_type: Optional[str] = None,
    time_range: Optional[str] = None,
    language: Optional[str] = None,
    region: Optional[str] = None,
    safe: Optional[str] = None,
    num: int = 10,
    site: Optional[str] = None,
    filetype: Optional[str] = None,
    exact_phrase: Optional[str] = None,
    exclude_terms: Optional[list] = None,
) -> str:
    """
    Build a Google search URL with all supported parameters.
    Mirrors buildSearchUrl() from search.ts.

    Args:
        query: Core search terms
        search_type: 'web'|'images'|'news'|'videos'|'shopping' (default: web)
        time_range: 'h'|'d'|'w'|'m'|'y' (hour/day/week/month/year)
        language: Language code e.g. 'en', 'ja', 'zh'
        region: Country code e.g. 'us', 'jp', 'cn'
        safe: 'off'|'medium'|'high'
        num: Results per page (default 10)
        site: Restrict to domain e.g. 'github.com'
        filetype: File type e.g. 'pdf', 'doc'
        exact_phrase: Exact phrase to match (will be quoted)
        exclude_terms: List of terms to exclude

    Returns:
        Full Google search URL string
    """
    # Build enhanced query with operators
    q = query.strip()
    if exact_phrase:
        q = f'"{exact_phrase}" {q}'
    if site:
        q = f'site:{site} {q}'
    if filetype:
        q = f'filetype:{filetype} {q}'
    if exclude_terms:
        q = f'{q} {" ".join("-" + t for t in exclude_terms)}'

    params = {"q": q.strip()}

    # Search type (tbm parameter)
    if search_type and search_type not in ("web", "all"):
        tbm = SEARCH_TYPE_MAP.get(search_type)
        if tbm:
            params["tbm"] = tbm

    # Time range (tbs parameter)
    if time_range:
        tbs = TIME_RANGE_MAP.get(time_range)
        if tbs:
            params["tbs"] = tbs

    # Language (hl = interface language, lr = language restrict)
    if language:
        params["hl"] = language
        params["lr"] = f"lang_{language}"

    # Region (gl = geolocation, cr = country restrict)
    if region:
        params["gl"] = region
        params["cr"] = f"country{region.upper()}"

    # Safe search
    if safe and safe != "off":
        params["safe"] = safe

    # Results per page
    if num and num != 10:
        params["num"] = str(num)

    return f"{GOOGLE_BASE}?{urlencode(params)}"


def is_captcha_url(url: str) -> bool:
    """
    Check if the URL indicates a CAPTCHA / bot detection page.
    Mirrors isBlockedUrl() from search.ts.
    """
    url_lower = url.lower()
    return any(pattern in url_lower for pattern in CAPTCHA_PATTERNS)


# JavaScript for extracting web search results from Google SERP.
# This is injected via page.evaluate() and returns a list of dicts.
EXTRACT_WEB_RESULTS_JS = """
(limit) => {
    const results = [], seen = new Set();
    const selectorSets = [
        { cont: '#search div[data-hveid]', snip: '.VwiC3b' },
        { cont: '#rso div[data-hveid]',    snip: '[data-sncf="1"]' },
        { cont: '.g',                      snip: 'div[style*="webkit-line-clamp"]' },
        { cont: 'div[jscontroller][data-hveid]', snip: 'div[role="text"]' }
    ];
    const altSnippets = ['.VwiC3b', '[data-sncf="1"]', 'div[style*="webkit-line-clamp"]', 'div[role="text"]'];

    for (const { cont, snip } of selectorSets) {
        if (results.length >= limit) break;
        for (const c of document.querySelectorAll(cont)) {
            if (results.length >= limit) break;
            const h = c.querySelector('h3');
            if (!h) continue;
            // Find link
            let a = h.querySelector('a');
            if (!a) {
                let el = h;
                while (el && el.tagName !== 'A') el = el.parentElement;
                a = (el instanceof HTMLAnchorElement) ? el : c.querySelector('a');
            }
            const url = a?.href;
            if (!url || !url.startsWith('http') || seen.has(url) || url.includes('google.com/')) continue;
            // Find snippet
            let snippet = c.querySelector(snip)?.textContent?.trim() || '';
            if (!snippet) {
                for (const sel of altSnippets) {
                    snippet = c.querySelector(sel)?.textContent?.trim() || '';
                    if (snippet) break;
                }
            }
            results.push({ title: h.textContent?.trim() || '', url, snippet });
            seen.add(url);
        }
    }
    // Fallback: generic anchor scan
    if (results.length < limit) {
        for (const a of document.querySelectorAll('a[href^="http"]')) {
            if (results.length >= limit) break;
            if (!(a instanceof HTMLAnchorElement)) continue;
            const url = a.href;
            if (!url || seen.has(url) || url.includes('google.com/') || url.includes('accounts.google')) continue;
            const title = a.querySelector('h3')?.textContent?.trim() || a.textContent?.trim();
            if (!title) continue;
            results.push({ title, url, snippet: '' });
            seen.add(url);
        }
    }
    return results.slice(0, limit);
}
"""

# JavaScript for extracting news results (uses Google's current DOM: .WlydOe links)
EXTRACT_NEWS_RESULTS_JS = """
(limit) => {
    const results = [], seen = new Set();
    // Primary: .WlydOe news article links with .SoaBEf containers
    for (const a of document.querySelectorAll('.WlydOe[href^="http"]')) {
        if (results.length >= limit) break;
        const url = a.href;
        if (!url || seen.has(url)) continue;
        const titleEl   = a.querySelector('.n0jPhd, .mCBkyc, .JtKRv');
        const snippetEl = a.querySelector('.UqSP2b, .HSSq5c, .GI74Re');
        const sourceEl  = a.querySelector('.MgUUmf, .NUnG9d');
        const timeEl    = a.closest('.SoaBEf')?.querySelector('.OSrXXb');
        let title = titleEl?.textContent?.trim() || '';
        if (!title) {
            const raw = a.querySelector('.SoAPf')?.textContent?.trim() || a.textContent?.trim() || '';
            const src = sourceEl?.textContent?.trim() || '';
            title = (src && raw.startsWith(src)) ? raw.slice(src.length).trim() : raw;
        }
        if (!title) continue;
        results.push({
            title,
            url,
            source: sourceEl?.textContent?.trim() || '',
            snippet: snippetEl?.textContent?.trim() || '',
            time: timeEl?.textContent?.trim() || ''
        });
        seen.add(url);
    }
    // Fallback: [data-hveid] with h3
    if (results.length === 0) {
        for (const c of document.querySelectorAll('[data-hveid]')) {
            if (results.length >= limit) break;
            const h = c.querySelector('h3, h4');
            if (!h) continue;
            const a = c.querySelector('a[href^="http"]');
            if (!a) continue;
            const url = a.href;
            if (seen.has(url)) continue;
            const time = c.querySelector('[class*="OSrXXb"], time');
            results.push({ title: h.textContent?.trim() || '', url, source: '', snippet: '', time: time?.textContent?.trim() || '' });
            seen.add(url);
        }
    }
    return results;
}
"""

# JavaScript for extracting image search results
EXTRACT_IMAGE_RESULTS_JS = """
(limit) => {
    return Array.from(document.querySelectorAll('img[data-src], img[src]'))
        .filter(img => {
            const src = img.src || img.dataset.src || '';
            return src.startsWith('http') && !src.includes('google.com') && img.naturalWidth > 50;
        })
        .slice(0, limit)
        .map(img => ({
            src: img.src || img.dataset.src,
            alt: img.alt || '',
            title: img.title || ''
        }));
}
"""
