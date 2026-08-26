# News Feed Data Contract

This is the contract between whatever generates news content (Hermes) and the
iOS app that consumes it. The app fetches `docs/latest.json` once per day (on
launch) and merges new articles into its own rolling 5-day local store by `id`.

It also reads `docs/archive/<YYYY-MM-DD>.json` — but only to fill a day it has
no stories for at all, such as after a fresh install or a few days away from the
app. The archive is a backstop, not the primary path: a 404 there is treated as
an ordinary quiet morning, not an error.

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
| `articles[].category` | string enum | One of: `local`, `national`, `northernIreland`, `global`, `tech`, `ai`. **Decoded strictly, and `articles` is a plain array** — a value the installed app doesn't know throws and fails the *whole feed*, not just that article. A new category ships in `NewsCategory.swift` and reaches the phone before any edition emits it. |
| `articles[].headline` | string | Short, single line. No period at the end, standard headline style. |
| `articles[].subtitle` | string | **20–50 words.** The teaser shown on the card — enough to decide whether to open the full article. Not a repeat of the headline. |
| `articles[].body` | string | **100–300 words of prose**, in the Markdown subset below. Length should match the story's actual complexity — don't pad simple stories to hit 300, and don't force complex stories into 100. |
| `articles[].imageURL` | string (URL), **optional** | Title photo, **self-hosted by us** — see "Photos" below. Path form: `/images/<id>.jpg` (relative) so it resolves against whatever host serves this JSON, **including a subpath** — GitHub Pages serves this repo from `/News-To-Me/`, and the app appends the path to that base rather than treating the leading slash as the host root. **May be omitted, `null`, or `""`** when a story has no photo; the app renders a category-tinted gradient instead. When a path *is* given, the file must exist in `docs/images/` — absent is acceptable, broken is not. |
| `articles[].sources` | array of `{name, url}` | 3–4 real source links used to research/write the story. Count is a judgment call — use as many as were actually needed to get a rounded picture, within that range. |
| `articles[].publishedAt` | ISO-8601 string | When the story was written/finalized. |

## `body` formatting

`body` is Markdown, but only this much of it:

| Syntax | Renders as |
|---|---|
| A blank line between blocks | A new paragraph |
| `## Subhead` | A crosshead within the story |
| `**bold**`, `*italic*` | Emphasis, inline |

That is the whole subset. **No `#`** — the headline owns that level. No lists, no
links, no images, no blockquotes, no code, no tables. The app parses exactly what
is in that table and nothing else; anything outside it renders as its own literal
characters, and `validate.mjs` warns rather than fails so a stray construct can't
hold an edition.

```json
"body": "The regional government declared a water-scarcity pre-alert across the whole eastern part of the community.\n\nThe declaration follows five months in which rainfall was 49 percent below the March-to-July average.\n\n## What the reservoirs show\n\nReservoirs in the Miño-Sil basin lost 57 cubic hectometres in the past week."
```

Three rules the validator checks, all as warnings:

- **Paragraphs run 30–80 words.** Over 80 reads as a wall of text on a phone.
- **Subheads only above 200 words.** A short story divided into parts is a short
  story with furniture on it. Most stories won't have any, and shouldn't.
- **A story opens on prose and ends on prose**, never on a subhead.

Subhead text is **not counted** toward the 100–300 range — that range has always
meant prose, and counting navigation would quietly shrink every structured story.

The exact numbers live in [`hermes/config.json`](hermes/config.json) under
`writing`, like every other tunable; the figures quoted here are illustrative.

**A body with no Markdown in it at all is valid** and renders as a single
paragraph. That is what every story published before this format existed looks
like, and the app holds a rolling 5 days of them.

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
      "northernIreland": { "min": 3, "max": 6, "sources": [] },
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
| `config.sections` | object | Keyed by category (`local`, `national`, `northernIreland`, `global`, `tech`, `ai`). Any key that isn't one of those is ignored by the app rather than failing the decode. Sections may be omitted. |
| `config.sections.<cat>.min` | int, optional | Lower end of the daily target. |
| `config.sections.<cat>.max` | int, optional | Upper end of the daily target. |
| `config.sections.<cat>.sources` | array of `{name, url?}`, optional | Sources drawn on for this section. `url` may be omitted for named pages that have no clean link; the app then shows the name alone. Defaults to `[]`. |

**This block is descriptive, not a control surface.** The app never writes it —
it reports what the generator did. `scripts/merge-sections.mjs` assembles it:
`min` and `max` are mirrored straight from
[`hermes/config.json`](hermes/config.json), and `sources` come from each
section's draft, being the outlets that section actually drew on. Changing
targets means editing the config, and the next edition reports the new numbers
on its own. The whole block is optional: a feed without it decodes fine, and
the app keeps showing the last config it saw.

## Categories, per day

Roughly **4–8 stories per category** (`local`, `national`, `northernIreland`,
`global`, `tech`, `ai`), driven by what's actually newsworthy that day — not
padded to a fixed count. A slow local-news day might only produce 2; a big tech
day might produce 8+.

## Ordering

The app presents articles **grouped by section**, in this fixed order:

```
local → national → northernIreland → global → tech → ai
```

Within a section, most significant story first. **The app presents a section in
exactly the order the articles appear in this file** — it records each article's
position on fetch and never re-sorts by date. Significance is the generator's
call, and `publishedAt` is a poor proxy for it: a lead story researched from a
morning source would otherwise fall below a lighter one filed later that day.

So the running order genuinely matters. Emit each section deliberately ranked.

Where several editions are held at once (the app keeps a rolling 5 days), the
newest edition's stories come first within a section, then the previous
edition's, each in its own emitted order. The app reads one edition at a time —
you pick a day first — so this ordering matters within a day, not across days.

## Photos

Photos are **self-hosted**, not hotlinked, so they can't rot out from under a
saved article. For each story the generator must:

1. Download the chosen photo. **Reject sources under 800px on the long edge or
   450px on the short edge** — a card photo fills roughly 1206 × 1311 physical
   pixels, and anything smaller visibly stretches.
2. Resize to **max 1600px on the long edge, JPEG quality ~75** (roughly
   150–250KB per file).
3. Save to `docs/images/<article-id>.jpg`.
4. Set `imageURL` to `/images/<article-id>.jpg`.

Steps 3 and 4 go together: a photo on disk whose `imageURL` was never written
back is invisible to the app. `fetch-photos.mjs` does both — check its exit
status rather than assuming it finished.

**A story with no photo still publishes.** If no suitable image can be found, or
every candidate is too small, omit `imageURL` and ship the story. The app has a
category-tinted fallback for exactly this, and one plainer card is a far better
outcome than holding an edition.

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

**Hosting is not specified here** — this document defines the data only. The feed
is served by GitHub Pages from `docs/` on `main`; see
[`ARCHITECTURE.md`](ARCHITECTURE.md) for how that fits together.

**Numbers are not specified here either.** Word counts, source counts and photo
dimensions all live in [`hermes/config.json`](hermes/config.json), which the
validator and the photo scripts read directly. Any figure quoted in this document
is illustrative — the config is what gets enforced.

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
