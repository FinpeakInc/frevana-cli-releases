---
name: x-scraper
description: Scrape X/Twitter profiles and posts, then generate structured reports with post content, engagement data, and links. Requires the frevana skill.
user_invocable: true
---

# X/Twitter Content Scraper

Scrape X/Twitter pages and produce structured Markdown reports.

## Prerequisites

This skill requires the **frevana** skill to be installed in the same pack.
Your `skillpack.json` must include both skills:

```json
{
  "skills": [
    {
      "name": "frevana",
      "source": "https://github.com/FinpeakInc/frevana-cli",
      "description": "Control Chrome browser to scrape web pages as Markdown."
    },
    {
      "name": "x-scraper",
      "source": "./skills",
      "description": "Scrape X/Twitter profiles and generate reports."
    }
  ]
}
```

## Workflow

### Step 1: Set up frevana

Follow the frevana skill's instructions to run its setup script and verify Chrome connection. Do NOT proceed until frevana reports `"chrome":"connected"`.

### Step 2: Scrape the X page

Use the frevana skill's scrape tool to fetch the target X/Twitter page. Pass the URL with `provider: "url"`.

For example, to scrape @elonmusk, call frevana_scrape with:
- `url`: `https://x.com/elonmusk`
- `provider`: `url`

### Step 3: Parse and format

From the returned Markdown, extract:
- Profile info (name, followers, following)
- Individual posts (content, date, engagement)
- Links and media references

Format as the output template below.

## Output Format

```markdown
# X Report: @username

## Profile
- **Name**: ...
- **Followers**: ...
- **Following**: ...

## Recent Posts

### Post 1
- **Date**: ...
- **Content**: ...
- **Engagement**: likes, reposts, replies
- **Link**: https://x.com/...

### Post 2
...
```

## Instructions

1. When the user provides an X/Twitter URL or @username, construct the full URL: `https://x.com/<username>`
2. Always run frevana setup first (via the frevana skill)
3. If the scrape returns login-page content or empty results, tell the user they need to be logged in to X on Chrome
4. If the user asks for a specific number of posts (e.g., "latest 5"), extract only that many
5. If frevana reports Chrome disconnected, tell the user to reconnect the extension

## Examples

User: `scrape @elonmusk on X`
→ Run frevana setup → scrape `https://x.com/elonmusk` via frevana → parse output → generate report

User: `get the latest 3 posts from @OpenAI`
→ Run frevana setup → scrape `https://x.com/OpenAI` via frevana → extract top 3 posts → generate report

User: `scrape this X thread https://x.com/someuser/status/123456`
→ Run frevana setup → scrape the thread URL via frevana → extract thread content → generate report
