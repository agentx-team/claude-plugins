# Google Search Operators Reference

## Query Operators (embed in `--query`)

| Operator | Syntax | Example | Effect |
|----------|--------|---------|--------|
| Exact phrase | `"..."` | `"machine learning"` | Only pages with exact phrase |
| Site restrict | `site:domain` | `site:github.com` | Limit to domain |
| File type | `filetype:ext` | `filetype:pdf` | Specific file type |
| Exclude term | `-word` | `python -snake` | Remove from results |
| OR | `word OR word` | `React OR Vue` | Either term |
| Title only | `intitle:word` | `intitle:tutorial` | Term must be in page title |
| URL only | `inurl:word` | `inurl:api` | Term must be in URL |
| Text only | `intext:word` | `intext:example` | Term in body text |
| Related | `related:url` | `related:nytimes.com` | Related sites |
| Cache | `cache:url` | `cache:example.com` | Google's cached version |
| Wildcard | `*` | `"best * framework"` | Matches any word |
| Number range | `n..m` | `iPhone $500..$800` | Price/number range |

## URL Parameters

### Base URL
```
https://www.google.com/search?q=<encoded-query>[&params]
```

### Search Type (`tbm`)
| Value | Type |
|-------|------|
| *(absent)* | Web (default) |
| `nws` | News |
| `isch` | Images |
| `vid` | Videos |
| `shop` | Shopping |

### Time Filter (`tbs`)
| Value | Range |
|-------|-------|
| `qdr:h` | Past hour |
| `qdr:d` | Past 24 hours |
| `qdr:w` | Past week |
| `qdr:m` | Past month |
| `qdr:y` | Past year |

### Language & Region
| Param | Purpose | Example |
|-------|---------|---------|
| `hl` | Interface language | `hl=en` |
| `lr` | Language restrict | `lr=lang_en` |
| `gl` | Geolocation | `gl=us` |
| `cr` | Country restrict | `cr=countryUS` |

### Other
| Param | Purpose |
|-------|---------|
| `safe` | `off`/`medium`/`high` |
| `num` | Results per page (max 100) |
| `start` | Pagination offset (0, 10, 20...) |

## Common Language Codes

| Code | Language |
|------|----------|
| `en` | English |
| `ja` | Japanese |
| `zh` | Chinese (Simplified) |
| `zh-TW` | Chinese (Traditional) |
| `ko` | Korean |
| `de` | German |
| `fr` | French |
| `es` | Spanish |
| `ru` | Russian |
| `ar` | Arabic |

## Common Country Codes

| Code | Country |
|------|---------|
| `us` | United States |
| `gb` | United Kingdom |
| `jp` | Japan |
| `cn` | China |
| `kr` | South Korea |
| `de` | Germany |
| `fr` | France |
| `ca` | Canada |
| `au` | Australia |
| `in` | India |

## Combined Examples

```bash
# Recent GitHub issues about playwright
python google_search.py --query "playwright" --site "github.com" --time d

# Academic PDFs about transformers
python google_search.py --query "transformer attention mechanism" --filetype pdf

# Exact phrase in English, US region
python google_search.py --query "tutorial" --exact "deep learning" --lang en --region us

# News from last week, exclude paid/sponsored
python google_search.py --query "AI news" --type news --time w --exclude "sponsored,advertisement"

# YouTube tutorials
python google_search.py --query "playwright automation tutorial" --site youtube.com
```
