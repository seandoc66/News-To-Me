# News Feed Data Contract

This is the contract between whatever generates news content (Hermes) and the
iOS app that consumes it. The app fetches a single JSON file — `docs/latest.json`
— once per day (on launch). It does not need history from the server: the app
keeps its own rolling 7-day local store and merges new articles into it by `id`.

## File: `docs/latest.json`

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
| `articles[].imageURL` | string (URL) | Title photo, **self-hosted by us** — see "Photos" below. Path form: `/images/<id>.jpg` (relative) so it resolves against whatever host serves this JSON, **including a subpath** — GitHub Pages serves this repo from `/News-To-Me/`, and the app appends the path to that base rather than treating the leading slash as the host root. Must point at a file that actually exists in `docs/images/`. |
| `articles[].sources` | array of `{name, url}` | 3–4 real source links used to research/write the story. Count is a judgment call — use as many as were actually needed to get a rounded picture, within that range. |
| `articles[].publishedAt` | ISO-8601 string | When the story was written/finalized. |

## `config` (optional)

An optional top-level block describing how the edition was assembled. The app
shows it read-only under the Sections button, so the sources and story targets
in play are visible on the phone without opening the repo.

```json
{
  "generatedAt": "2026-07-28T06:00:00Z",
  "config": {
    "sections": {
      "local":    { "min": 3, "max": 6, "sources": [
        { "name": "El Progreso", "url": "https://www.elprogreso.es" },
        { "name": "Concello de Lugo press page" }
      ]},
      "national": { "min": 3, "max": 6, "sources": [] },
      "global":   { "min": 2, "max": 5, "sources": [] },
      "tech":     { "min": 2, "max": 4, "sources": [] },
      "ai":       { "min": 1, "max": 3, "sources": [] }
    }
  },
  "articles": []
}
```

| Field | Type | Rules |
|---|---|---|
| `config.sections` | object | Keyed by category (`local`, `national`, `global`, `tech`, `ai`). Any key that isn't one of those is ignored by the app rather than failing the decode. Sections may be omitted. |
| `config.sections.<cat>.min` | int, optional | Lower end of the daily target. |
| `config.sections.<cat>.max` | int, optional | Upper end of the daily target. |
| `config.sections.<cat>.sources` | array of `{name, url?}`, optional | Sources drawn on for this section. `url` may be omitted for named pages that have no clean link; the app then shows the name alone. Defaults to `[]`. |

**This block is descriptive, not a control surface.** The app never writes it —
it reports what the generator did. Changing targets or sources means editing the
generator's brief in `HERMES_HANDOFF.md`, then reflecting the change here on the
next run. The whole block is optional: a feed without it decodes fine, and the
app keeps showing the last config it saw.

## Categories, per day

Roughly **4–8 stories per category** (`local`, `national`, `global`, `tech`, `ai`),
driven by what's actually newsworthy that day — not padded to a fixed count. A
slow local-news day might only produce 2; a big tech day might produce 8+.

## Ordering

The app presents articles **grouped by section**, in this fixed order:

```
local → national → global → tech → ai
```

Within a section, most significant story first. **The app presents a section in
exactly the order the articles appear in this file** — it records each article's
position on fetch and never re-sorts by date. Significance is the generator's
call, and `publishedAt` is a poor proxy for it: a lead story researched from a
morning source would otherwise fall below a lighter one filed later that day.

So the running order genuinely matters. Emit each section deliberately ranked.

Where several editions are held at once (the app keeps a rolling 7 days), the
newest edition's stories come first within a section, then the previous
edition's, each in its own emitted order.

## Photos

Photos are **self-hosted**, not hotlinked, so they can't rot out from under a
saved article. For each story the generator must:

1. Download the chosen photo.
2. Resize to **max 1000px on the long edge, JPEG quality ~75** (keeps each file
   roughly 60–120KB).
3. Save to `docs/images/<article-id>.jpg`.
4. Set `imageURL` to `/images/<article-id>.jpg`.

Steps 3 and 4 go together: a photo on disk whose `imageURL` was never written
back is invisible to the app, and validation rejects the batch. `fetch-photos.mjs`
does both — check its exit status rather than assuming it finished.

**Rolling window:** the app caches every image to disk on first view and keeps
cached copies for saved articles indefinitely, so the server only needs to hold
a photo long enough for the app to fetch it once. To stop the git repo growing
without bound, **delete image files older than 14 days** in the same commit that
adds new ones. (Git history retains deleted blobs, so without this the repo grows
by roughly 1GB/year permanently.)

*Upgrade path if repo size ever becomes a problem:* move images to object storage
and put the returned absolute CDN URL in `imageURL` instead. The schema already
supports this — `imageURL` may be either a relative path or an absolute URL, and
the app handles both.

**Hosting is not specified here.** Where `latest.json` and `images/` are served
from is Hermes' decision; see section 6 of [`HERMES_HANDOFF.md`](HERMES_HANDOFF.md)
for the requirements any choice has to meet. This document only defines the data.

**Licensing note:** prefer openly-licensed images (Wikimedia Commons, Unsplash,
government/press-release imagery, or the outlet's own Open Graph image) over
scraping agency wire photos. This feed is private, single-user, and never
redistributed, which keeps it firmly in personal-use territory — but preferring
open licenses avoids the question entirely.

## Validation

Before publishing, run `scripts/validate.mjs` against the generated JSON. If it
fails, **do not overwrite `docs/latest.json`** — leave the previous day's file
in place and surface the error instead.

## Archive (optional)

Each day's batch may also be written to `docs/archive/YYYY-MM-DD.json` for
debugging/backfill purposes. The app never reads this — it's for humans only.
