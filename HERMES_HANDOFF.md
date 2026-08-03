# Hermes Operating Brief — Daily Personal News Feed

**This is the standing brief for a pipeline that is already live**, not a setup
task. The feed has been running since 31 July: hosting is chosen, the cron is
scheduled, the app is pointed at it and installed. What follows is what you need
every morning.

The pipeline is working. Read this when something changes or something breaks.

| | |
|---|---|
| **Fixed** | The JSON contract (section 2). The app decodes exactly this; deviating breaks it silently. |
| **Fixed** | Photos are self-hosted, never hotlinked (section 5). A missing photo no longer blocks the edition. |
| **Yours** | How you source and research the news. Sections 3–4 set the standards, not the method. |

Repo root is the working directory for everything below (`docs/`, `scripts/`):
`/Users/shanedoc/Sites/News-To-Me`

### Changed recently

- **3 Aug** — `imageURL` is now **optional**. A story with no photo publishes
  anyway and renders with a category-tinted gradient. See section 5.
- **3 Aug** — photos are now resized to **1600px** rather than 1000px, and
  sources under 800×450 are rejected as too small. See section 5.
- **3 Aug** — the validator now warns when two articles cite the same story URL
  (a duplicate published across two sections) and when a source link points at a
  masthead rather than the story. See sections 4 and 7.
- **3 Aug** — an independent watchdog now checks the live feed each morning and
  emails Shane if no fresh edition arrived. See section 6.

---

## ⚠️ Outstanding right now — 3 August edition unpublished

**The live feed is still 2 August.** Today's batch was written and is correct,
but never published: two stories had no photo, and under the old rules that
blocked the whole edition. Under the new rules **it now passes validation.**

You were right not to publish. The rule was wrong, not your handling of it.

Three things to settle before publishing, then run the commands at the end of
section 8:

1. **`tech-002` (Go 1.27) — its photo already exists.**
   `docs/images/2026-08-03-tech-002.jpg` is on disk, 62KB. The download worked;
   the path was simply never written back into the article. Set
   `"imageURL": "/images/2026-08-03-tech-002.jpg"`.

2. **`ai-002` (EU AI Act) — genuinely has no photo.** Find one, or publish it
   without. Both are fine now.

3. **`tech-001` and `ai-001` are the same story.** OpenAI's Astra model solving
   ten open maths problems, same four sources, byte-identical photo. Drop one —
   see the duplicate rule in section 4.

**Your report for this run had two errors worth understanding**, because they
point at the run rather than the news. It named `tech-003` (Seedance) as needing
a photo — `tech-003` has one. And it described `tech-002` as missing a photo when
the file was on disk. Together that suggests in-run state drifted from what was
actually written. **Worth checking whether articles get renumbered mid-run**:
`id` is load-bearing, since the app tracks Shane's saved stories by it, and an id
shifting between what you think you wrote and what lands on disk could detach a
saved story.

Delete this section once the edition is out.

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

### One story, once — the duplicate rule

**A story appears in exactly one section, once per edition.** This is the rule
most often broken, and the most irritating one to break in a feed read once a
day.

It happens because sections overlap, not because of carelessness:

| Overlap | Put it in |
|---|---|
| An AI model, lab, or AI policy story | `ai` — never also `tech` |
| A Spanish story with an international dimension | `national` — Spain is the angle Shane wants |
| A Lugo or Galicia story that made the national press | `local` — the closer section wins |
| A tech story that is mostly EU/Spanish regulation | whichever section Shane would look for it in, not both |

**The closer, more specific section always wins.** When genuinely torn, pick one
and drop the other — never hedge by running both.

Cross-posting is only defensible when the two pieces are genuinely different
stories that happen to touch the same subject: different angle, different facts,
**different sources**. If they share a source URL, they are the same story.

The validator flags two articles citing the same story URL, which is the reliable
signal — reworded headlines defeat any headline comparison. Treat that warning as
a duplicate until you have shown otherwise.

> This has been happening. On 3 August the OpenAI Astra maths story ran as both
> `tech-001` and `ai-001` with identical sources and a byte-identical photo. The
> already-published 2 August edition contains four more pairs: Ceuta across
> `global` and `national`, the EU AI Act across `tech` and `ai`, and the Suno
> copyright ruling likewise.

### Don't repeat yesterday either

Before writing, read the previous few days of `docs/archive/*.json` and avoid
re-covering stories already sent. A genuinely developing story may be revisited,
but only with a new angle and a headline that makes the development clear.

---

## 5. Photos — self-hosted, FIXED

**Photos are hosted by us. Never put a third-party URL in `imageURL`.** Give
every story a photo where you reasonably can, but a story without one still
publishes — see below.

Self-hosting is deliberate: the app caches photos to disk and keeps them for
saved articles indefinitely, so a story Shane saved six months ago must still
have its picture. Hotlinked images rot.

**One photo per story, and only one.** The app crops it to fill the top half of
the card and shows the same file, smaller, in the header when the story is
opened. Shane likes that — don't supply separate images for the two, and don't
change the shape of what you provide.

For each story:

1. **Find a relevant photo.** Grab the Open Graph image from the source article,
   or any news photo that genuinely illustrates *that* story — a generic stock
   laptop photo on every tech story defeats the point. Shane cares about the
   photos.
2. **Download it, resize to max 1600px on the long edge, JPEG quality ~75**
   (roughly 150–250KB per file).
3. **Save as `docs/images/<article-id>.jpg`** and set `imageURL` to
   `/images/<article-id>.jpg`.

### Minimum resolution — reject anything too small

A card photo fills the full width and half the height of the screen: about
**1206 × 1311 physical pixels** on Shane's phone. A source smaller than that gets
stretched, and it shows.

`fetch-photos.mjs` now **rejects any source below 800px on its long edge or 450px
on its short edge** and reports it as a failed photo. That story then publishes
without a picture, which looks far better than a pixelated one.

So when choosing a candidate, **prefer the largest version available**. Open Graph
images are usually 1200×630, which is fine. Article thumbnails and list-view
images often are not — follow through to the full-size original where the page
offers one.

If the only image available is too small, that is a legitimate no-photo story.
Publish it without one.

> On 2 August a local story ran with a visibly pixelated portrait. The main cause
> was on our side — the resize ceiling was 1000px, so every photo was being
> upscaled about 2.3× to fill the card. That ceiling is now 1600px. The minimum
> check above covers the other half of the problem.

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

## 6. How publishing works, and how failure gets noticed

**GitHub Pages**, serving the `docs/` folder on `main`. The feed lives at
`https://seandoc66.github.io/News-To-Me/`, `latest.json` at its root and photos
under `/images/`. Publishing is `git push` — Pages auto-deploys. No tokens, no
service connections, no manual steps. `latest.json` is served with
`max-age=600`, short enough that the phone never reads a stale copy for long.

The app is pointed at that base URL and resolves `/images/<id>.jpg` against it.

### Two independent checks now catch a missed edition

Silence used to be the failure mode. On 3 August a batch correctly refused to
publish, the previous day's file stayed live, and nobody knew for two days —
a stale feed is indistinguishable from a quiet news day if nothing says
otherwise. Two things now say otherwise:

1. **The app** compares the edition's `generatedAt` against the clock on every
   refresh. Past 26 hours it shows a banner — *"No new edition today — showing
   yesterday's news"*. Shane sees it the moment he opens the app.
2. **A GitHub Actions watchdog** (`.github/workflows/feed-watchdog.yml`) fetches
   the live URL each morning at 06:00 UTC and fails the workflow if the edition
   is over 24 hours old, unreachable, or empty. GitHub emails Shane on failure.

The watchdog checks the **published URL**, not the repo, so it exercises the
whole chain including the Pages deploy. It is deliberately independent of you:
you can report your own aborts, but you cannot report never having run at all,
and that is the failure most likely to go unnoticed.

**This does not replace your own reporting.** The watchdog says only that
something is wrong; your report says what. Keep writing it.

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

## 9. Reporting each run

Write a short report every run. It is the only account of what happened, and the
watchdog in section 6 only says *that* something is wrong, never *what*.

Say plainly:

- Whether the edition **published**, and if not, why.
- Any story that shipped **without a photo**, and any you couldn't source one for.
- Any **validator warnings**, especially duplicate-source and dead-end-link ones.
- Anything that looked wrong but you worked around.

**Check the report against the files before sending it.** On 3 August the report
named the wrong story as missing a photo, and named a story whose photo was
present on disk. A report that disagrees with the repo sends whoever reads it
after the wrong problem.

If something needs changing on the app side — a contract change, a new field,
anything Claude Code has to implement — say so explicitly rather than assuming
it will be noticed.

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

---

## 11. Optional `config` block

The feed may carry a `config` object alongside `articles`, describing the story
counts each section aims for:

```json
{
  "generatedAt": "2026-08-03T06:00:00+02:00",
  "config": {
    "sections": {
      "local":    { "min": 3, "max": 6 },
      "national": { "min": 3, "max": 6 },
      "global":   { "min": 2, "max": 5 },
      "tech":     { "min": 2, "max": 4 },
      "ai":       { "min": 1, "max": 3 }
    }
  },
  "articles": []
}
```

It is **descriptive, not instructive** — the app displays it read-only on the
Sections screen so Shane can see what the feed is aiming for. It does not change
what you produce; section 3 still governs that, and real newsworthiness still
beats hitting a number.

The block is optional and absent is fine, but the validator checks its shape when
present, since a malformed one would silently drop sections from that screen.

Letting Shane *edit* these from the phone would need a way for the app to send
changes back, which does not exist. That is an open design question, not
something to implement against.
