# Hermes Task Spec — Daily Personal News Feed

You are being asked to produce and publish a daily news feed for Shane's personal
iOS app. The app is built and working; it is waiting on a live feed URL.

This document is the complete brief. Two things in it are **fixed** and two are
**yours to decide**:

| | |
|---|---|
| **Fixed** | The JSON contract (section 2). The app already decodes exactly this. |
| **Fixed** | Photos are self-hosted, never hotlinked (section 5). |
| **Yours** | Where the feed is hosted and how it gets published (section 6). |
| **Yours** | How you source and research the news (section 3–4 set the standards, not the method). |

When you are done, **write a handoff document back** telling Shane and Claude
Code what you decided, so the app can be pointed at your feed. Section 9 lists
exactly what that needs to contain.

Repo: `/Users/shanedoc/Sites/News-To-Me`
| Working directory for everything below: the repo root (`docs/`, `scripts/`). |

---

## 1. Configuration

| Setting | Value |
|---|---|
| **Local news area** | **Lugo, Galicia, Spain.** The city and its province. |
| **National news country** | **Spain.** |
| Output language | **English, always** — even when the source material is Spanish or Galician. |
| Run frequency | Once per day, early morning. Suggested 06:00 Europe/Madrid. |

Most Lugo and Spanish coverage is in Spanish or Galician. Read it in the original
and write in English. Do **not** restrict sourcing to English-language outlets —
that would gut local coverage.

### Sources by section

| Section | Sources |
|---|---|
| **local** | *El Progreso*, *La Voz de Galicia*, *El Correo Gallego*, *Noticias Lugo*, Concello de Lugo press page, Deputación de Lugo press page |
| **national** | *El País*, *El Mundo*, *RTVE*, *20minutos*, *Público*, *Europa Press* |
| **global** | Reuters, BBC, AP, The Guardian |
| **tech** | Hacker News, TechCrunch, Wired, VentureBeat, The Verge, arXiv |
| **ai** | Simon Willison's blog (simonwillison.net), Anthropic blog, OpenAI blog, plus general tech sources above |

### Future: configurable sources & story counts

A future app feature should let Shane manage sources and daily story counts per
section from within the iOS app. This will require extending the JSON contract
(see section 11).

---

## 2. The JSON contract — FIXED

One file, `latest.json`. The iOS app decodes exactly this structure. Deviating
breaks the app silently, so `validate.mjs` (section 7) enforces every rule below.

```json
{
  "generatedAt": "2026-07-31T06:00:00Z",
  "articles": [
    {
      "id": "2026-07-31-tech-001",
      "category": "tech",
      "headline": "Rocket Lab Wins Its Largest Contract to Date",
      "subtitle": "A $266 million US Space Force award covers twelve suborbital launches with options for six more, flown mostly from a new site at Kodiak, Alaska, in support of missile defence testing.",
      "body": "Rocket Lab has been awarded a $266 million contract by the US Space Force, the largest launch contract in the company's history. … (100-300 words of plain prose)",
      "imageURL": "/images/2026-07-31-tech-001.jpg",
      "sources": [
        { "name": "Rocket Lab", "url": "https://rocketlabcorp.com/updates/record-contract-rslp-kodiak/" },
        { "name": "The Defense Post", "url": "https://thedefensepost.com/2026/07/29/rocket-lab-us-launch-contract/" },
        { "name": "GlobeNewswire", "url": "https://www.globenewswire.com/news-release/2026/07/27/3333334/0/en/Rocket-Lab-Awarded-Record-266M-Missile-Defense-Contract-with-U-S-Space-Force-for-Suborbital-Launches.html" }
      ],
      "publishedAt": "2026-07-27T10:00:00Z"
    }
  ]
}
```

### Field reference

| Field | Type | Rule |
|---|---|---|
| `generatedAt` | ISO-8601 string | When this batch was built. |
| `articles` | array | See below. |
| `articles[].id` | string | **`YYYY-MM-DD-category-NNN`**, e.g. `2026-07-31-local-003`. `NNN` starts at `001` within each category each day. **Must be unique and stable.** The app tracks saved articles by `id` — never reuse an `id` for a different story, and never re-issue a different `id` for the same story. |
| `articles[].category` | string enum | Exactly one of: `local`, `national`, `global`, `tech`, `ai`. No other values. |
| `articles[].headline` | string | Short, single line, headline style, **no trailing period**. Keep under ~120 characters or it wraps awkwardly on a phone. |
| `articles[].subtitle` | string | **20–50 words.** The teaser on the card, and the single most important field — most stories are only ever read at this length. It must *add* information, not restate the headline. |
| `articles[].body` | string | **100–300 words.** Plain prose only: no markdown, no headings, no bullet lists. |
| `articles[].imageURL` | string | Path to the self-hosted photo. Normally `/images/<id>.jpg`, resolved by the app against the feed's base URL. An absolute `https://…` URL is also accepted. |
| `articles[].sources` | array | **3–4** objects, each `{ "name": string, "url": string }`. Real, working URLs. |
| `articles[].publishedAt` | ISO-8601 string | Roughly when the story broke. |

### Ordering — FIXED

Emit articles **grouped by section**, in this order, most significant story first
within each section:

```
local → national → global → tech → ai
```

The app also sorts defensively, but emit them sorted anyway.

---

## 3. Volume and editorial judgment

Roughly **4–8 stories per category**, driven entirely by what is genuinely
newsworthy that day.

**Do not pad to hit a number.** A quiet local news day that yields two real
stories is a correct outcome; five padded non-stories is a failure. Equally, if
something significant is unfolding, eight is fine. An empty category produces a
validator warning, not an error — that is deliberate.

---

## 4. Writing each story

**Headline** — short, factual, headline style, no trailing period.

**Subtitle (20–50 words)** — what Shane reads to decide whether to open the
story. Add detail the headline doesn't carry. Never a reworded headline.

**Body (100–300 words)** — *match the length to the story*. A council decision
may be complete in 110 words; a shifting geopolitical situation may genuinely
need 290. Never inflate with scene-setting, context-padding, or "it remains to be
seen" filler to reach a word count.

Write in clear, neutral, factual reporting style. **Rewrite and synthesise — never
copy sentences verbatim from any outlet.** Where facts are contested between
sources, say so briefly rather than silently picking one version. Be sceptical of
vendor and press-release claims; attribute contested figures to whoever claimed
them.

**Sources (3–4)** — the places you actually researched from. Shane clicks these.
Every URL must be real and resolve. **Never invent a plausible-looking URL.** Read
as many sources as you need for a rounded picture, then list the 3–4 most useful.
Prefer primary sources (filings, official statements, papers) alongside reporting.

### Don't repeat yesterday

Before writing, read the previous few days of `public/archive/*.json` and avoid
re-covering stories already sent. A genuinely developing story may be revisited,
but only with a new angle and a headline that makes the development clear.
Repeats are the most irritating possible failure in a feed read once a day.

---

## 5. Photos — self-hosted, FIXED

**Every story needs a title photo, and you host it yourself. Never put a
third-party URL in `imageURL`.**

This is deliberate: the app caches photos to disk and keeps them for saved
articles indefinitely, so a story Shane saved six months ago must still have its
picture. Hotlinked images rot.

For each story:

1. **Find a relevant photo.** Grab the Open Graph image from the source article,
   or any news photo that genuinely illustrates *that* story — a generic stock
   laptop photo on every tech story defeats the point. Shane cares about the
   photos.
2. **Download it, resize to max 1000px on the long edge, JPEG quality ~75**
   (roughly 60–120KB per file).
3. **Save as `docs/images/<article-id>.jpg`** and set `imageURL` to
   `/images/<article-id>.jpg`.

`scripts/fetch-photos.mjs` will do steps 2–3 for you: put a
`photoCandidate: { url, description, license }` on each article in your draft and
run it. It verifies the response is actually an image rather than an HTML error
page, resizes via `sips`, rewrites `imageURL`, and exits non-zero listing any
story whose photo failed. It throttles and retries, but **note that some image
hosts rate-limit hard** — if you are pulling many photos from one origin, expect
429s and pace accordingly. You are free to ignore this script and do it yourself.

### What if a story has no good photo? — PUBLISH ANYWAY

**A missing photo must never block the edition.** This changed on 3 August, after
a missing image held back a complete, otherwise-correct feed of sixteen stories
for a whole day.

`imageURL` is **optional**. If after reasonable effort there is no suitable photo,
either omit the `imageURL` key entirely or set it to an empty string, and publish
the story anyway. The app renders those cards with the category-tinted gradient
that already exists for photos that fail to load — it looks deliberate, not
broken. One plainer card costs far less than a day with no news.

Two things still *are* errors, because they indicate a bug rather than an
unlucky story:

- An `imageURL` that points at a file which isn't on disk. Absent is fine; broken
  is not.
- **More than half** the batch missing photos. That isn't a run of bad luck, it's
  the photo step having failed, and it's worth stopping for.

Never pad with a generic image that adds nothing — an empty `imageURL` is the
better outcome. And don't drop a genuinely interesting story just because it has
no picture; publish it.

### Rolling 14-day window

**In the same commit that adds today's photos, delete photos older than 14 days:**

```
node scripts/prune-images.mjs
```

The app caches every photo on first view, so the server only needs to hold one
long enough to be fetched once. Without pruning, git history grows by roughly
1GB/year permanently — deleted blobs stay in history forever. The script never
deletes anything still referenced by `latest.json`, whatever its age.

---

## 6. Hosting — DECIDED: GitHub Pages

**Chosen: GitHub Pages** via the `docs/` folder on `main`.

The feed lives at `https://seandoc66.github.io/News-To-Me/`. Publishing is fully automated: commit to `main` and GitHub Pages auto-deploys from the `docs/` folder. No tokens, no service connections, no manual steps.

Requirements met:
1. **Publicly reachable over HTTPS** — GitHub Pages provides HTTPS by default.
2. **Stable URL** — `https://seandoc66.github.io/News-To-Me/latest.json` won't change.
3. **No long cache on latest.json** — GitHub Pages serves with `max-age=600` (10 min), which is short enough for daily updates.
4. **Images at derivable URLs** — `/images/<id>.jpg` resolves against the base URL.
5. **Not served from this Mac Mini** — GitHub handles hosting.
6. **Fully automatable** — `git push` is the publish step.
7. **Free** — GitHub Pages is free for public repos.

---

## 7. Validation — not optional

```
node scripts/validate.mjs                       # checks docs/latest.json
node scripts/validate.mjs path/to/draft.json    # checks a draft
```

It enforces every hard rule in section 2 — word counts, id format and uniqueness,
category names, source count and URL validity, duplicate headlines, and timestamp
format. It exits non-zero and prints **every** problem it found, not just the
first.

**If validation fails, do not publish.** Leave the previous day's `latest.json`
in place. Yesterday's feed staying live is far better than a broken or empty one.

### Read the warnings — they are the quality signal

Warnings do not block publication, and three of them are worth acting on:

- **`… cite the same source … check these aren't the same story published twice`**
  Two articles sharing a story URL almost always means one story written twice,
  usually split across `tech` and `ai`, which overlap heavily. Reworded headlines
  sail past the exact-match headline check, so this is what actually catches it.
  **This has already happened** — on 3 August, the OpenAI Astra maths story ran as
  both `tech-001` and `ai-001` with identical photos and identical sources. Merge
  or drop one.
- **`… is a section or home page …, it's a dead end when tapped`**
  A source of `https://www.bbc.com/news` is useless: Shane taps it expecting the
  story and gets a masthead. Link the article itself.
- **`… article(s) publishing without a photo`**
  Informational. Fine in small numbers; see section 5.

---

## 8. Daily process

All commands run from the repo root.

```
1. Read docs/archive/*.json for the last ~3 days          (avoid repeats)

2. Research and write the stories. Save the draft as
   docs/archive/YYYY-MM-DD.json, with a photoCandidate on each article.

3. Fetch and resize photos:
      node scripts/fetch-photos.mjs docs/archive/YYYY-MM-DD.json
   Re-running only retries what is still missing.

   It exits non-zero if any photo failed. Make ONE reasonable attempt at
   replacements for those, then MOVE ON — set their imageURL to "" and
   continue. A missing photo is not a reason to hold the edition.

   Check the JSON actually matches what is on disk before continuing. On
   3 August a photo downloaded successfully but its path was never written
   back into the article, so a story that had its picture was reported as
   missing one — and the report named the wrong story on top of that.

4. Validate the draft:
      node scripts/validate.mjs docs/archive/YYYY-MM-DD.json

5. If validation FAILS → stop. Do NOT touch docs/latest.json.
   Report the errors.
   Read the WARNINGS too, even when it passes — see section 7.

6. If validation PASSES → publish it:
      cp docs/archive/YYYY-MM-DD.json docs/latest.json

7. Prune photos older than 14 days:
      node scripts/prune-images.mjs

8. Final check against the live file:
      node scripts/validate.mjs

9. Commit and push to main — GitHub Pages auto-deploys.
```

---

## 9. What to hand back — REQUIRED

When you have the pipeline working and a feed live, write a handoff document for
Shane and Claude Code. The app currently points at a placeholder and **cannot
fetch anything until it has your answers.** It must contain:

1. **The exact, full URL of `latest.json`.** e.g.
   `https://example.github.io/News-To-Me/latest.json`
2. **The base URL that relative image paths resolve against**, and one **real
   example image URL** so it can be verified with `curl`.
3. **Confirmation it is publicly reachable with no authentication**, ideally with
   the `curl -I` output showing the status and `Cache-Control` header for both
   `latest.json` and an image.
4. **What you chose and why**, briefly — enough that Shane can reason about it
   later without re-deriving your decision.
5. **How publishing works**, concretely: the exact command or job that runs, what
   time it runs, where it runs from, and whether anything (a token, a workflow
   file, a service connection) had to be set up that Shane should know exists.
6. **How it fails, and how you would notice.** If a run fails or the source of a
   photo goes down, what happens — and does Shane find out, or does the feed just
   quietly stop updating?
7. **Anything you changed in this repo**, so nothing is a surprise.

Claude Code will then set `FeedEndpoint.base` in
`NewsApp/Networking/FeedService.swift` and verify the app end to end against your
live feed.

---

## 10. Notes

**A first run does not have to be perfect.** Run it manually a few times and read
the output before letting it go unattended. It is worth checking a couple of
articles by eye for tone and length before trusting it daily.

**Licensing.** This feed is private, single-user, and never redistributed, which
keeps it in personal-use territory. Preferring openly-licensed images avoids the
question entirely.

**If the repo grows uncomfortably** despite the 14-day window, moving photos to
object storage and using absolute URLs in `imageURL` needs no app change — the
schema already accepts them.

**There is a draft batch already in the repo** at
`docs/archive/2026-07-31.json`: 14 real articles with verified sources, of which
only 2 have photos fetched. Treat it as a worked example of the format, or
overwrite it with your first real run — Shane has no attachment to it.

---

## 11. Future app features (for Claude Code)

### Configurable sources & story counts

Add a settings screen in the iOS app that lets Shane manage which sources are
used per section and how many stories to aim for daily. This will require
extending the JSON contract — likely a `config` object alongside `articles`:

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

The app would write this config back to a file or send it to the feed pipeline.
The exact mechanism (API endpoint, config file in the repo, etc.) is to be
decided.

### Auto-delete unsaved stories after 1 week

Stories that Shane has not saved (hearted) should be automatically deleted from
the device after 7 days. Saved stories persist indefinitely. This is purely an
app-side feature — the feed pipeline only publishes what's new each day.
