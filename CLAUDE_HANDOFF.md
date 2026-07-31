# Handoff to Claude Code — News-To-Me iOS App

This document tells you everything you need to point the iOS app at the live feed and implement the requested features.

---

## 1. Feed URL

| What | Value |
|------|-------|
| **latest.json** | `https://seandoc66.github.io/News-To-Me/latest.json` |
| **Image base** | `https://seandoc66.github.io/News-To-Me/` (images at `/images/<id>.jpg`) |
| **Example image** | `https://seandoc66.github.io/News-To-Me/images/2026-07-31-local-001.jpg` |

Both return `200 OK` with no authentication required. `latest.json` is served with `Cache-Control: max-age=600` (10 minutes) — short enough for daily updates. Images are served with standard GitHub Pages caching.

## 2. How publishing works

The feed is produced by a Hermes Agent cron job that runs daily at **06:00 Europe/Madrid**. It:

1. Researches news from the sources listed in `HERMES_HANDOFF.md`
2. Writes stories and saves them to `docs/archive/YYYY-MM-DD.json`
3. Fetches and resizes photos to `docs/images/<id>.jpg`
4. Validates against the JSON contract
5. Copies to `docs/latest.json`
6. Commits and pushes to `main`

GitHub Pages auto-deploys from the `docs/` folder on `main`. No manual steps.

> **For full details on how news is sourced, editorial standards, photo sourcing, and the daily pipeline, see [`HERMES_HANDOFF.md`](./HERMES_HANDOFF.md)** — that's the complete operational brief for the feed.

## 3. What to set in the app

Set `FeedEndpoint.base` in `NewsApp/Networking/FeedService.swift` to:

```
https://seandoc66.github.io/News-To-Me
```

The app fetches `latest.json` from that base URL and resolves image paths like `/images/<id>.jpg` against it.

## 4. JSON contract

The app decodes exactly this structure. Do not deviate.

```json
{
  "generatedAt": "2026-07-31T06:00:00Z",
  "articles": [
    {
      "id": "2026-07-31-local-001",
      "category": "local",
      "headline": "Headline text here",
      "subtitle": "20-50 word teaser",
      "body": "100-300 words of plain prose",
      "imageURL": "/images/2026-07-31-local-001.jpg",
      "sources": [
        { "name": "Source Name", "url": "https://..." }
      ],
      "publishedAt": "2026-07-30T09:20:00Z"
    }
  ]
}
```

**Field rules:**
- `id`: `YYYY-MM-DD-category-NNN` format. Unique and stable — the app tracks saved articles by `id`.
- `category`: One of `local`, `national`, `global`, `tech`, `ai`. No other values.
- `headline`: Under ~120 chars, no trailing period.
- `subtitle`: 20-50 words. Must add information, not restate the headline.
- `body`: 100-300 words. Plain prose only — no markdown, no headings, no lists.
- `sources`: 3-4 objects with real URLs.
- `imageURL`: Relative path `/images/<id>.jpg` or absolute `https://...` URL.

Articles are ordered by section: `local → national → global → tech → ai`, most significant first within each section.

## 5. Changes made to the repo

- Moved `feed-data/` contents to repo root (scripts, docs/, schema.md, vercel.json)
- Renamed `public/` to `docs/` for GitHub Pages compatibility
- Updated script paths from `public/` to `docs/`
- Updated `HERMES_HANDOFF.md` with sources table and photo policy
- Repo renamed from `iOS-News-App` to `News-To-Me`
- Repo made public

## 6. Features requested by Shane (implement these in the app)

### 6a. Configurable sources & story counts per section

Add a settings screen in the iOS app that lets Shane manage:

- Which sources are used per section
- How many stories to aim for daily (min/max per section)

This will require extending the JSON contract. Proposed approach:

```json
{
  "generatedAt": "2026-07-31T06:00:00Z",
  "config": {
    "sections": {
      "local": { "min": 3, "max": 6 },
      "national": { "min": 3, "max": 6 },
      "global": { "min": 2, "max": 5 },
      "tech": { "min": 2, "max": 4 },
      "ai": { "min": 1, "max": 3 }
    }
  },
  "articles": []
}
```

The exact mechanism (app writes config to a file in the repo, sends to an API endpoint, etc.) is yours to decide. Discuss with Shane.

### 6b. Auto-delete unsaved stories after 1 week

Stories that Shane has not saved (hearted/bookmarked) should be automatically deleted from the device after **7 days**. Saved stories persist indefinitely.

This is purely an app-side feature — the feed pipeline only publishes what's new each day. The app already tracks saved articles by `id` — use that to determine what to keep.

### 6c. Sources by section (for reference)

| Section | Sources |
|---------|---------|
| **local** | El Progreso, La Voz de Galicia, El Correo Gallego, Noticias Lugo, Concello de Lugo press page, Deputación de Lugo press page |
| **national** | El País, El Mundo, RTVE, 20minutos, Público, Europa Press |
| **global** | Reuters, BBC, AP, The Guardian |
| **tech** | Hacker News, TechCrunch, Wired, VentureBeat, The Verge, arXiv |
| **ai** | Simon Willison's blog (simonwillison.net), Anthropic blog, OpenAI blog |

---

That's everything. Once you've set `FeedEndpoint.base` and verified the app loads the feed end-to-end, you're done.
