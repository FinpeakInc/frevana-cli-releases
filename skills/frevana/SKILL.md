---
name: frevana
description: Control Chrome browser to scrape web pages as Markdown, ask AI platforms questions, and publish to social media. Auto-installs on first use. Uses your logged-in browser sessions — no API keys needed.
user_invocable: true
---

# Frevana — Browser Scraping, AI Chat & Social Publishing

Control your real Chrome browser to scrape any web page, ask AI platforms questions, and publish to social media. Uses your logged-in sessions — no API keys needed.

## Prerequisites

- **Google Chrome** installed and open
- **Frevana Chrome extension**: Download from https://static.frevana.com/app-updates/extension/frevana-extension.zip, unzip, then load in Chrome via `chrome://extensions/` → Enable "Developer mode" → "Load unpacked" → select the unzipped folder
- **Node.js 18+**, **npm**, **git**, **curl** (for auto-installation)

Everything else (frevana-cli, daemon) is installed and started automatically.

## Finding the scripts

This skill bundles scripts in the `scripts/` directory. Before running any script, you must locate this skill's directory. Read this SKILL.md file's path to determine the skill directory, then use absolute paths:

```bash
# Example: if this SKILL.md is at /path/to/skills/frevana/SKILL.md
# then scripts are at /path/to/skills/frevana/scripts/
FREVANA_SKILL_DIR="$(dirname "$(find / -path '*/skills/frevana/SKILL.md' -print -quit 2>/dev/null)")"
```

However, the simplest approach: **you already know this file's path from how you loaded it. Use that to construct the scripts path.**

## Before every use — MANDATORY

**Step 1:** Determine the absolute path to this skill's directory from this SKILL.md file's location.

**Step 2:** Run setup (replace `SKILL_DIR` with the actual absolute path):

```bash
bash SKILL_DIR/scripts/setup.sh
```

**Step 3:** Read the JSON output and act on it:

- `"chrome":"connected"` — proceed to tool calls
- `"chrome":"disconnected"` — **STOP. Do NOT proceed.** Tell the user:
  1. Open Google Chrome
  2. Install the Frevana extension (link in Prerequisites) if not installed
  3. Click the Frevana extension icon and press **Reconnect**
  4. Then ask the user to try again
- `"status":"error"` — **STOP.** Tell the user the exact error message

**Do NOT call any frevana tool until setup returns `"chrome":"connected"`.** If Chrome is disconnected, tell the user and stop. Do not try to scrape anyway.

## Scrape a web page

```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_scrape '{"url":"https://example.com","provider":"url"}'
```

Parameters:
- `url` (required) — URL to scrape
- `provider` — Use `"url"` for clean Markdown extraction via Readability.js
- `timeout` — Timeout in ms (default: 60000)

Returns clean Markdown with title, author, content, and links.
Uses Chrome login sessions — can access paywalled/authenticated content if the user is logged in.

## Ask an AI platform

```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"chatgpt","prompt":"your question here"}'
```

Parameters:
- `prompt` (required) — The question to send
- `provider` — `chatgpt`, `gemini`, `perplexity`, `deepseek`, `doubao`, `google`, `google-ai`, `google-maps`, `amazon-rufus`, `amazon-product`, `amazon-product-reviews`, `amazon-price`, `amazon-rufus-qa` (default: chatgpt)
- `timeout` — Timeout in ms (default: 120000)

Note: The user must be logged in to the AI platform in Chrome for this to work.

## Search X posts by topic

```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_x_search_topic '{"topic":"vibe coding"}'
```

Parameters:
- `topic` (required) — Topic or query to search on X
- `sort` — `"top"` or `"live"` (default: `top`)
- `count` — Number of posts to fetch (default: 20, max: 100)
- `fetchMode` — `"quick"` or `"full"` (default: `full`)
- `cursor` — Optional cursor to continue from a previous result set
- `includeReplies` — Include replies when available
- `includeQuotes` — Include quotes when available
- `includeMedia` — Include media metadata when available
- `maxScrollRounds` — Maximum scroll rounds during collection
- `minCount` — Minimum number of posts to collect before stopping
- `timeout` — Timeout in ms (default: 45000)

Example:

```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_x_search_topic '{"topic":"vibe coding","sort":"live","count":10,"fetchMode":"quick","timeout":60000}'
```

Requirements:
- The user must be logged in to X in Chrome
- X search may require a higher timeout for busy topics

## Search Meta Ads Library

Use the dedicated Meta Ads tool for ad research. It returns structured advertisement records rather than generic page text. The country filter defaults to `ALL`; ad category and media type remain set to all. The extension loads results until no new ads are available or the requested limit is reached.

```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_meta_ads_search '{"keyword":"nike","country":"CN","active_status":"active","date_from":"2026-01-01","date_to":"2026-06-22","maxResults":20,"timeout":120000}'
```

Parameters:
- `keyword` (required) — advertiser name, brand, or ad keyword
- `country` — `ALL` (default) or an ISO 3166-1 alpha-2 country code: `CN` for China, `AM` for Armenia, `US` for the United States
- `active_status` — `active`, `inactive`, or `all` (default)
- `date_from` — Inclusive start date in `YYYY-MM-DD`; defaults to six months before today
- `date_to` — Inclusive end date in `YYYY-MM-DD`; defaults to today
- `maxResults` — Maximum number of ads to return (default: 20, max: 500)
- `timeout` — Timeout in ms (default: 120000; effective range: 10000–180000)

The result includes search metadata plus semantic fields for each ad, such as advertiser, status, dates, ad text, landing-page URL, and creative image/video/card data when available.

Requirements:
- Chrome must be open with the Frevana extension connected
- The Meta Ads Library page must be accessible in Chrome; sign in to Facebook if Meta asks for it

## Publish to social media

```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_publish '{"provider":"twitter","text":"Hello world!"}'
```

Parameters:
- `provider` (required) — `twitter`, `facebook`, `linkedin`
- `text` (required) — Post content (plain text for Twitter/Facebook, HTML for LinkedIn)
- `mode` — LinkedIn only. `"post"` (default) for a short feed update, `"article"` for a long-form article
- `title` — LinkedIn article mode only. Required when `mode` is `"article"`
- `cover_image` — LinkedIn article mode only. URL or base64 data URL of the cover image (optional)
- `timeout` — Timeout in ms. Defaults: post=30000, LinkedIn article=120000

### LinkedIn post (short feed update)
```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_publish '{"provider":"linkedin","text":"Just shipped a new feature!"}'
```

### LinkedIn article (long-form)
```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_publish '{"provider":"linkedin","mode":"article","title":"My article title","text":"Article body content...","timeout":180000}'
```

With cover image:
```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_publish '{"provider":"linkedin","mode":"article","title":"My article","text":"Body...","cover_image":"https://example.com/cover.jpg","timeout":180000}'
```

**Important — LinkedIn article body formatting:** The article body is typed character-by-character into LinkedIn's ProseMirror editor, which strips HTML tags. So `<b>`, `<a>`, `<i>` etc. become plain text. Pass plain text (with newlines for paragraphs) — do not expect HTML formatting to render.

## Amazon product research

**CRITICAL: All Amazon providers REQUIRE a full Amazon product URL in the `prompt` parameter.**
The prompt must contain a URL like `https://www.amazon.com/dp/B0XXXXXXXX`. Without a URL, the providers will fail because they cannot locate the Rufus widget or product page. Amazon timeouts can be 60–120 seconds — **never retry within the same conversation turn**; if a call returns an error, stop and tell the user.

```bash
# Ask Amazon Rufus AI a question about a specific product
# Format: URL + space + your question
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"amazon-rufus","prompt":"https://www.amazon.com/dp/B0XXXXXXXX Is this laptop good for programming?","timeout":120000}'

# Extract product details (title, price, rating, reviews, images)
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"amazon-product","prompt":"https://www.amazon.com/dp/B0XXXXXXXX","timeout":60000}'

# Fetch top 100 helpful reviews from a product (paginated; default maxReviews=100)
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"amazon-product-reviews","prompt":"https://www.amazon.com/dp/B0XXXXXXXX","timeout":180000}'

# Same, but cap at 50 reviews via JSON config in the prompt
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"amazon-product-reviews","prompt":"https://www.amazon.com/dp/B0XXXXXXXX {\"maxReviews\":50}","timeout":120000}'

# Extract price and discount info
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"amazon-price","prompt":"https://www.amazon.com/dp/B0XXXXXXXX","timeout":60000}'

# Get all Q&A pairs from Rufus AI widget
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"amazon-rufus-qa","prompt":"https://www.amazon.com/dp/B0XXXXXXXX","timeout":180000}'
```

Amazon providers:
- `amazon-rufus` — Ask Rufus AI a question about a product. **Prompt format:** `<URL> <your question>`. Example: `"https://www.amazon.com/dp/B01NBKTPTS Does this work with M1 Mac?"`
- `amazon-product` — Extract structured product info. **Prompt:** just the product URL.
- `amazon-product-reviews` — Fetch top N helpful reviews (default 100, max 500) for a product. **Prompt:** product URL or bare ASIN, optionally followed by a JSON blob like `{"maxReviews":50,"sortBy":"helpful","reviewerType":"all_reviews","filterByStar":"five_star"}`. **Requires the user to be logged in to Amazon.**
- `amazon-price` — Extract price, discount, and coupon info. **Prompt:** just the product URL.
- `amazon-rufus-qa` — Batch extract all suggested Q&A pairs from the Rufus AI widget. **Prompt:** just the product URL.

Requirements:
- The user must be logged in to Amazon in Chrome
- **ALL 4 Amazon providers require an actual product page URL** (must contain `/dp/<ASIN>` or `/gp/product/<ASIN>`), NOT `amazon.com` homepage, search results, or category pages. Example: `https://www.amazon.com/dp/B01NBKTPTS` ✓, `https://www.amazon.com/` ✗
- Amazon calls are slow (30–120 seconds). Set a high `timeout` and wait for the result. Never retry mid-turn — if it fails, tell the user why and ask what to do next.
- If the user gives you a non-product URL or just a product name, tell them you need a product page URL. Do NOT try to search for the product yourself — Amazon's search page doesn't work with these providers.

## Check connection status

```bash
bash SKILL_DIR/scripts/frevana-call.sh frevana_status '{}'
```

- `"connected":true` — Chrome extension is connected
- `"connected":false` — not connected, tell user to reconnect

## Troubleshooting

If a tool call fails, follow this sequence:

1. Re-run `bash SKILL_DIR/scripts/setup.sh` — check the output
2. If `"chrome":"disconnected"`:
   - Is Chrome open? Open it.
   - Is the Frevana extension installed? Check `chrome://extensions/`. If not, download from https://static.frevana.com/app-updates/extension/frevana-extension.zip, unzip, load via "Load unpacked"
   - Click the Frevana extension icon → press **Reconnect**
   - Re-run setup
3. If `"status":"error"`:
   - `"git is not installed"` → user needs to install git
   - `"npm install failed"` → check network, check Node.js version (`node -v`, needs 18+)
   - `"Daemon process crashed"` → check log at `/tmp/frevana-daemon.log`
   - `"Port in use"` → another process is on port 12306, kill it or set `FREVANA_PORT=12307`
4. If `frevana-call.sh` times out:
   - For large pages, set `FREVANA_TIMEOUT=300` before calling
   - The page might require login — user must be logged in on Chrome
5. If scrape returns empty or login page content:
   - The user is not logged in to that site in Chrome
   - Ask them to open Chrome, visit the site, log in, then retry

## Configuration

Environment variables (optional):
- `FREVANA_PORT` — daemon port (default: 12306)
- `FREVANA_TIMEOUT` — curl timeout in seconds for frevana-call.sh (default: 180)

## Instructions

1. **Always run setup first** and check the output before any tool call
2. **Do NOT proceed if Chrome is disconnected** — tell the user how to fix it and stop
3. Default scrape provider is `"url"` (Readability.js extraction)
4. Default ask provider is `"chatgpt"` unless the user specifies otherwise
5. Use `frevana_x_search_topic` for X/Twitter topic search requests
6. If a call fails, follow the Troubleshooting section step by step
7. When scraping fails with login/auth content, explain that the user must be logged in to that site in Chrome
8. Replace `SKILL_DIR` in all commands with the actual absolute path to this skill's directory

## Examples

User: `scrape https://news.ycombinator.com`
```bash
bash SKILL_DIR/scripts/setup.sh
# Check output — only proceed if "chrome":"connected"
bash SKILL_DIR/scripts/frevana-call.sh frevana_scrape '{"url":"https://news.ycombinator.com","provider":"url"}'
```

User: `ask Gemini to explain quantum computing`
```bash
bash SKILL_DIR/scripts/setup.sh
# Check output — only proceed if "chrome":"connected"
bash SKILL_DIR/scripts/frevana-call.sh frevana_ask '{"provider":"gemini","prompt":"explain quantum computing"}'
```

User: `tweet "Just shipped v2.0!"`
```bash
bash SKILL_DIR/scripts/setup.sh
# Check output — only proceed if "chrome":"connected"
bash SKILL_DIR/scripts/frevana-call.sh frevana_publish '{"provider":"twitter","text":"Just shipped v2.0!"}'
```
