"""
google-search skill scripts

Modules:
    search_utils   -- URL builder, CAPTCHA detector, DOM extraction JS strings
    google_search  -- Main search CLI and perform_search() / get_page_html() API
"""

from .search_utils import (
    build_search_url,
    is_captcha_url,
    EXTRACT_WEB_RESULTS_JS,
    EXTRACT_NEWS_RESULTS_JS,
    EXTRACT_IMAGE_RESULTS_JS,
)

from .google_search import perform_search, get_page_html

__all__ = [
    "build_search_url",
    "is_captcha_url",
    "EXTRACT_WEB_RESULTS_JS",
    "EXTRACT_NEWS_RESULTS_JS",
    "EXTRACT_IMAGE_RESULTS_JS",
    "perform_search",
    "get_page_html",
]
