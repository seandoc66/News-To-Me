# Hermes Task Spec — Daily News Feed

This is the complete brief for generating the daily news feed consumed by the
personal iOS news app. It is written to be run unattended, once per day.

**Scheduling is not set up by this document.** Shane decides when and how this
runs — whether via cron, a Hermes scheduled task, or manually on demand. Run it
manually a few times first and read the output before trusting it unattended.

Repo: `/Users/shanedoc/Sites/iOS-News-App`
Working directory for everything below: `feed-data/`

---

## 0. Configuration to confirm before first run

| Setting | Value |
|---|---|
| **Local news area** | **Lugo, Galicia, Spain.** City and surrounding province. |
| **National news country** | **Spain.** |
| Output language | English, always — even when the source material is in another language. |
| Run time | Early morning, before Shane wakes up. Suggested 06:00 Europe/Madrid. |

Most Lugo and Spanish national coverage will be in Spanish or Galician. Read it
in the original and write the article in English — do not restrict sourcing to
English-language outlets, which would badly thin out local coverage. Useful
starting points for `local`: *El Progreso* (Lugo), *La Voz de Galicia*, *Cadena
SER Lugo*, the Concello de Lugo and Deputación de Lugo press pages. For
`national`: *El País*, *El Mundo*, *RTVE*, *20minutos*, *Público*.

Everything else below is fixed by the data contract in [`schema.md`](schema.md).

---

## 1. What to produce

One JSON file, `public/latest.json`, matching [`schema.md`](schema.md) exactly.
Read that file — it is the authority on field names, types and limits. This
document covers editorial judgment and process; `schema.md` covers structure.

### Categories and volume

Five sections. Roughly **4–8 stories each**, driven entirely by what is
genuinely newsworthy that day:

| Category | Scope |
|---|---|
| `local` | The local area (see configuration above). |
| `national` | The national picture (see configuration above). |
| `global` | International news of real consequence. |
| `tech` | Technology, software, hardware, science-adjacent. |
| `ai` | AI specifically — models, research, policy, industry. |

**Do not pad to hit a number.** A quiet local news day producing 2 stories is a
correct outcome; five padded non-stories is a failure. Equally, if something big
is unfolding in one section, 8 is fine.

### Ordering

Emit articles grouped by section in this order, most significant story first
within each section:

```
local → national → global → tech → ai
```

---

## 2. Writing each story

For every story, produce:

**Headline** — short, single line, standard headline style, no trailing period.

**Subtitle — 20 to 50 words.** This is the teaser Shane reads on the card to
decide whether to open the story. It must add information, not restate the
headline in different words. This is the single most important field in the feed:
most stories will only ever be read at this length.

**Body — 100 to 300 words.** *Match the length to the story.* A council planning
decision may be complete in 110 words. A shifting geopolitical situation may
genuinely need 290. Never inflate a simple story with context-padding,
scene-setting, or "it remains to be seen" filler to reach a word count. Plain
prose, no markdown, no headings, no bullet lists.

Write in clear, neutral, factual reporting style. Rewrite and synthesise from the
sources — do not copy sentences verbatim from any outlet. Where facts are
contested between sources, say so briefly rather than picking one silently.

**Sources — 3 to 4 real links.** These are the places the story was actually
researched from, and Shane clicks through to them. Read as many sources as
needed to get a rounded picture; list the 3–4 most useful. Every URL must be
real and resolve — never invent a plausible-looking URL. Prefer primary sources
(official statements, filings, papers) alongside reporting.

**ID** — `YYYY-MM-DD-category-NNN`, e.g. `2026-07-28-local-003`. Sequence starts
at `001` within each category each day. IDs must be stable: the app tracks
saved articles by ID, so never re-issue an ID for a different story.

---

## 3. Photos

Every story needs a title photo. Photos are **self-hosted**, not hotlinked, so
they can't disappear from under a story Shane saved months ago.

**`scripts/fetch-photos.mjs` does the download and resizing for you.** Write the
draft JSON with a `photoCandidate: { url, description, license }` on each
article, then run it — it downloads, verifies the response is genuinely an image
(not an HTML error page), resizes via `sips`, writes
`public/images/<article-id>.jpg`, and rewrites `imageURL` to match.

So the only editorial work is step 1:

1. **Find a relevant photo** and record it as `photoCandidate`. Prefer
   openly-licensed or public-domain sources: Wikimedia Commons, Unsplash,
   government and institutional press imagery, or the outlet's own Open Graph
   image. Avoid agency wire photos where an openly-licensed alternative exists.
   The URL must point directly at an image file, not at a page containing one.
2. Run `node scripts/fetch-photos.mjs <draft.json>`. It exits non-zero and lists
   any story whose photo failed, so you can find a replacement and re-run.

The photo should genuinely illustrate the story. A generic stock image of a
laptop for every tech story defeats the point — Shane cares about the photos.

### Housekeeping — 14-day image window

**In the same commit that adds today's images, delete image files older than 14
days:**

```
node scripts/prune-images.mjs
```

The app caches every photo to disk on first view and keeps saved articles' photos
permanently, so the server only needs to hold a photo long enough to be fetched
once. The script never deletes anything still referenced by `latest.json`,
whatever its age.

This matters: git retains deleted blobs in history forever, so without the
rolling window the repo grows by roughly 1GB/year permanently.

---

## 4. Don't repeat yesterday

Before writing, **read the previous few days of `public/archive/*.json`** and
avoid re-covering stories already sent. A genuinely developing story may be
revisited, but only with a new angle and a headline that makes the development
clear — not a reworded version of yesterday's card. Repeats are the most
irritating possible failure mode for a feed read once a day.

---

## 5. Process

All commands run from `feed-data/`.

```
1. Read public/archive/*.json for the last ~3 days       (avoid repeats)

2. Research and write the stories, including a photoCandidate for each.
   Save as public/archive/YYYY-MM-DD.json

3. Fetch and resize the photos:
      node scripts/fetch-photos.mjs public/archive/YYYY-MM-DD.json
   Exits non-zero if any photo failed — find replacements and re-run.

4. Validate:
      node scripts/validate.mjs public/archive/YYYY-MM-DD.json

5. If validation FAILS → stop. Do NOT touch public/latest.json.
   Report the errors. Yesterday's feed stays live, which is a far better
   outcome than a broken or empty one.

6. If validation PASSES → copy it over public/latest.json
      cp public/archive/YYYY-MM-DD.json public/latest.json

7. Prune old photos:
      node scripts/prune-images.mjs

8. Final check against the live file:
      node scripts/validate.mjs

9. Commit and push from the repo root:
      git add -A && git commit -m "Feed for YYYY-MM-DD" && git push
```

The push triggers a Vercel deploy automatically; the app picks up the new feed
the next time Shane opens it.

### Validation is not optional

`scripts/validate.mjs` enforces every hard limit in the contract — word counts,
category names, ID format and uniqueness, source count, timestamp format, and
that every referenced image file actually exists on disk. It exits non-zero on
failure and prints every problem it found. Warnings (section ordering, headline
style, unusual category counts) are advisory but worth reading.

---

## 6. Notes and escape hatches

**If the repo grows uncomfortably large** despite the 14-day window, move photos
to Vercel Blob storage and put the returned absolute CDN URL in `imageURL`
instead. The schema and the app already accept absolute URLs, so this needs no
app change.

**If a day's research genuinely turns up nothing** for a category, emit no
articles for it. The app renders whatever sections are present. An empty
category produces a validator warning, not an error.

**Licensing:** this feed is private, single-user, and never redistributed, which
keeps it in personal-use territory. Preferring openly-licensed images avoids the
question entirely.
