# News Feed Data Contract

This is the contract between whatever generates news content (Hermes) and the
iOS app that consumes it. The app fetches a single JSON file — `public/latest.json`
— once per day (on launch). It does not need history from the server: the app
keeps its own rolling 7-day local store and merges new articles into it by `id`.

## File: `public/latest.json`

```json
{
  "generatedAt": "2026-07-28T06:00:00Z",
  "articles": [
    {
      "id": "2026-07-28-tech-001",
      "category": "tech",
      "headline": "Apple Ships New Chip Architecture for 2027 iPhones",
      "subtitle": "Leaked roadmap documents describe a redesigned chip family aimed at cutting power draw nearly in half, with mass production starting next spring.",
      "body": "Full 100-300 word rewritten/summarized article text goes here...",
      "imageURL": "https://images.example.com/2026-07-28-tech-001.jpg",
      "sources": [
        { "name": "The Verge", "url": "https://www.theverge.com/..." },
        { "name": "Bloomberg", "url": "https://www.bloomberg.com/..." }
      ],
      "publishedAt": "2026-07-28T05:40:00Z"
    }
  ]
}
```

## Field reference

| Field | Type | Rules |
|---|---|---|
| `generatedAt` | ISO-8601 string | Timestamp this batch was generated. |
| `articles` | array | See below. Order doesn't matter — the app sorts/groups as it likes. |
| `articles[].id` | string | **Stable and unique.** Format: `YYYY-MM-DD-category-NNN` (e.g. `2026-07-28-local-003`). Must not change if the same story is re-published — the app uses this to dedupe and to track "saved" state across days. |
| `articles[].category` | string enum | One of: `local`, `national`, `global`, `tech`, `ai`. |
| `articles[].headline` | string | Short, single line. No period at the end, standard headline style. |
| `articles[].subtitle` | string | **20–50 words.** The teaser shown on the card — enough to decide whether to open the full article. Not a repeat of the headline. |
| `articles[].body` | string | **100–300 words.** Length should match the story's actual complexity — don't pad simple stories to hit 300, and don't force complex stories into 100. Plain prose, no markdown. |
| `articles[].imageURL` | string (URL) | Title photo, **self-hosted by us** — see "Photos" below. Path form: `/images/<id>.jpg` (relative) so it resolves against whatever host serves this JSON. Must point at a file that actually exists in `public/images/`. |
| `articles[].sources` | array of `{name, url}` | 3–4 real source links used to research/write the story. Count is a judgment call — use as many as were actually needed to get a rounded picture, within that range. |
| `articles[].publishedAt` | ISO-8601 string | When the story was written/finalized. |

## Categories, per day

Roughly **4–8 stories per category** (`local`, `national`, `global`, `tech`, `ai`),
driven by what's actually newsworthy that day — not padded to a fixed count. A
slow local-news day might only produce 2; a big tech day might produce 8+.

## Ordering

The app presents articles **grouped by section**, in this fixed order:

```
local → national → global → tech → ai
```

Within a section, most significant story first. The generator should emit
articles already in this order (the app also sorts defensively, so a
mis-ordered file still renders correctly — but emit them sorted anyway).

## Photos

Photos are **self-hosted**, not hotlinked, so they can't rot out from under a
saved article. For each story the generator must:

1. Download the chosen photo.
2. Resize to **max 1000px on the long edge, JPEG quality ~75** (keeps each file
   roughly 60–120KB).
3. Save to `public/images/<article-id>.jpg`.
4. Set `imageURL` to `/images/<article-id>.jpg`.

**Rolling window:** the app caches every image to disk on first view and keeps
cached copies for saved articles indefinitely, so the server only needs to hold
a photo long enough for the app to fetch it once. To stop the git repo growing
without bound, **delete image files older than 14 days** in the same commit that
adds new ones. (Git history retains deleted blobs, so without this the repo grows
by roughly 1GB/year permanently.)

*Upgrade path if repo size ever becomes a problem:* move images to Vercel Blob
storage and put the returned absolute CDN URL in `imageURL` instead. The schema
already supports this — `imageURL` may be either a relative path or an absolute
URL, and the app handles both.

**Licensing note:** prefer openly-licensed images (Wikimedia Commons, Unsplash,
government/press-release imagery, or the outlet's own Open Graph image) over
scraping agency wire photos. This feed is private, single-user, and never
redistributed, which keeps it firmly in personal-use territory — but preferring
open licenses avoids the question entirely.

## Validation

Before publishing, run `scripts/validate.js` against the generated JSON. If it
fails, **do not overwrite `public/latest.json`** — leave the previous day's file
in place and surface the error instead.

## Archive (optional)

Each day's batch may also be written to `public/archive/YYYY-MM-DD.json` for
debugging/backfill purposes. The app never reads this — it's for humans only.
