---
name: content-tweaks
description: Change what the daily News-To-Me feed contains or how it reads — sources and outlets, output language, story count, word/paragraph lengths, subheads, tone, and how photos are sourced, sized, cropped, chosen and fallen back on. Use whenever Shane asks to tweak, adjust, add, drop, lengthen, shorten or reword anything about the feed's content or its images, e.g. "add El Salto to national", "make tech stories shorter", "stop using subheads", "write local in Spanish", "more sources per story", "photos look soft", "stop cropping the tops off", "try harder before giving up on a photo". Not for app UI, layout, colours or Swift code.
---

# Content tweaks

Shane reads the feed every morning and comes back with one or two small
requests about the content. This skill turns those requests into the right
edit, in the right file, and leaves the two files consistent with each other.

The feed is generated once a day at 06:00 by Hermes reading `hermes/brief.md`.
**No tweak takes effect until the next morning's run.** Say so when reporting.

## The two files that decide content

Everything content-related lives in exactly two places, both at the repo root
(`/Users/shanedoc/Sites/News-To-Me`):

| File | What belongs there |
|---|---|
| `hermes/config.json` | Every **number, name and list** — outlets, languages, word counts, story counts, photo limits, search caps. |
| `hermes/brief.md` | Every **judgement rule** — tone, structure, what wins when sections overlap, when a subhead is earned, how to handle a quiet day. |

The split is load-bearing. `config.json` is read at run time by
`scripts/validate.mjs`, `fetch-photos.mjs` and `prune-images.mjs` as well as by
Hermes, so a number changed there is actually enforced. `brief.md` refers to
those values by path (`config.json → writing.bodyWords`) and never repeats the
number itself.

**Never write a literal number into `brief.md`.** If a request needs a number
that has no home in `config.json`, add the key to `config.json` and reference it
from `brief.md`. Duplicating it is the one failure mode this structure exists to
prevent — the prose that looks authoritative stops matching what runs.

`schema.md` is the JSON contract the iOS app decodes. It is **not** a content
knob; only touch it if a tweak genuinely needs a new field, and say so loudly
because the app needs a code change and a reinstall to read it.

## Routing a request

### Sources and outlets → `config.json → sources`

One array per section (`local`, `national`, `global`, `tech`, `ai`). Add,
remove or reorder entries there. They are starting points, not a closed list —
Hermes follows a story off-list — so "add X" means "expect X", not "restrict to
X". If Shane wants a hard restriction or a ban ("never use the Daily Mail"),
that's a judgement rule: state it in `brief.md` near the sources paragraph,
because an array can't express a prohibition.

Entries are plain names (`"El Progreso"`), optionally with a domain hint where
the name is ambiguous (`"Simon Willison's blog (simonwillison.net)"`).

### Languages → `config.json → locale`

- `outputLanguage` — the language stories are **written in**. One value for the
  whole feed.
- Source language is deliberately unconstrained: `brief.md` tells Hermes to
  read Spanish and Galician coverage and write in the output language anyway.
  Don't narrow that without Shane asking — it would gut local coverage.

Wants a **different language per section** (e.g. local in Spanish, rest in
English)? `outputLanguage` is a single string. Change it to an object keyed by
section, or add `locale.languageOverrides`, then update the `brief.md` sentence
that points at it. Nothing in the scripts reads `outputLanguage`, so no
validator change is needed — but the app shows one masthead in one language, so
mention that mixed-language editions will look mixed.

### Length, shape and formatting → mostly `config.json → writing`

| Request | Key |
|---|---|
| Card blurb longer/shorter | `subtitleWords` |
| Stories longer/shorter | `bodyWords` |
| Paragraphs longer/shorter, fewer walls of text | `paragraphWords` |
| More/fewer subheads | `subheadsAboveWords` (raise it → fewer) |
| More/fewer source links per story | `sourcesPerArticle` |
| More/fewer stories per section | `sections.storiesPerSection` |

All of these are **checked by `scripts/validate.mjs`**, so changing them changes
what warns and what fails. `bodyWords` counts prose only — subhead text is
excluded. `paragraphWords.min` is guidance for the writer; only `max` is
checked.

**Subheads off entirely** isn't a number — it's a rule. Say it in the "Subheads
are the exception" part of `brief.md`. Same for anything about *where* a
paragraph breaks, whether a story may open on a subhead, or which Markdown is
allowed: the permitted subset (blank-line paragraphs, `## `, sparing
`**bold**`/`*italic*`) is enforced by the validator's `OUTSIDE_SUBSET` list, so
**adding** a syntax (lists, blockquotes, links in the body) needs an edit to
`scripts/validate.mjs` too, not just prose. Flag that cost before doing it.

### Tone and quality → `hermes/brief.md`, "Writing each story"

Neutrality, scepticism about vendor claims, attributing contested figures,
saying so when sources disagree, never copying sentences verbatim, no
"it remains to be seen" filler. Edit the existing sentences rather than
appending a new section — the brief is read cover to cover each morning and
grows stale fast if requests pile up as addenda.

### Photos

Photos have three layers, and a request lands in one of them. Work out which
before editing anything.

```
brief.md            what makes a good photo, and what to do without one
config.json→photos  the numbers the pipeline enforces
fetch-photos.mjs    the download/resize mechanics — code, not config
```

**How the pipeline actually works**, so you can predict what a change does:

1. Hermes writes a `photoCandidate: { url, description, license }` onto each
   article in the draft.
2. `scripts/fetch-photos.mjs` downloads it with a real User-Agent, following
   redirects; rejects anything whose content-type isn't `image/*` (almost
   always an HTML page URL rather than the image itself) or under 1KB.
3. Rejects sources smaller than `minSourceLongEdge` × `minSourceShortEdge`.
4. Resizes with `sips -Z maxLongEdge` at `jpegQuality`, writes
   `docs/images/<article-id>.jpg`, sets `imageURL` to `/images/<id>.jpg` and
   deletes `photoCandidate`.
5. Re-running only retries what's still missing, so a partial failure is cheap.

#### Size and cropping

The knobs are `photos.maxLongEdge` and nothing else — **the scripts never
crop**. `sips -Z` scales the long edge and preserves aspect ratio, and it only
ever downsizes; a source smaller than the target stays small.

Cropping happens on the phone, at display time: the app crops the one stored
file to fill the top half of a card (roughly **1206 × 1311 physical pixels** —
slightly taller than wide) and shows the same file again, smaller, in the story
header. That has two consequences worth telling Shane when he asks about photo
quality:

- **`maxLongEdge` below ~1311 guarantees every photo is upscaled to fill**,
  which is exactly what "the photos look soft" means. 1600 gives headroom.
  Raising it further mostly buys file size, not visible sharpness.
- **Wide photos lose their edges.** A 1200 × 630 Open Graph image cropped to a
  taller-than-wide card keeps roughly the middle third horizontally. That is a
  composition rule, not a number — it belongs in `brief.md`: prefer a photo
  whose subject sits near the centre, and distrust one whose point is at the
  left or right edge or in a caption bar along the bottom.

There is **one file per story, not two**. Don't add a separate thumbnail or
header image; the brief says so explicitly and the app expects one URL.

#### Quality

`photos.jpegQuality` (currently 75) is the sips `formatOptions` value.
Raising it toward 90 costs repo size on every photo, every day, forever — these
are committed to a public git repo and pruned on a rolling window, so it
compounds. If the complaint is "photos look bad", check `maxLongEdge` and the
crop first; JPEG quality is rarely the culprit at this size.

`minSourceLongEdge` / `minSourceShortEdge` (800 / 450) are the reject
threshold, and they are a **direct trade**:

- Raise them → sharper cards, more stories publish with no photo at all.
- Lower them → fewer bare cards, more stretched, soft ones.

Say which way you've traded when you change them. If Shane wants "better
photos" without more bare cards, the answer is usually in `brief.md` — tell
Hermes to follow through to the full-size original rather than taking the
list-view thumbnail — not in the thresholds.

#### When there's no suitable photo

This is settled policy in `brief.md` and worth restating before changing it: a
missing photo **never blocks the edition**. `imageURL` is optional; omit it or
set it to `""` and publish. The app renders a category-tinted gradient that
looks deliberate. One plainer card costs far less than a day with no news, and
an interesting story is never dropped just for having no picture.

Two things stay errors, because they mean broken rather than unavailable:

- `imageURL` pointing at a file that isn't on disk — a hard validator failure.
- More than half the batch missing photos — the validator says so loudly,
  because that's the photo step having failed, not an unlucky day.

The escalation on a failed fetch is: **one reasonable attempt at a replacement,
then set `imageURL` to `""` and move on.** If Shane wants more persistence
(try N candidates, always fall back to a Wikimedia Commons image of the place
or organisation), that's a `brief.md` change to the step-3 instructions in
"The run". If he wants *less* — never substitute, first candidate or nothing —
same place. Don't express either as a number in `config.json`; there's no key
for it and the scripts wouldn't read one.

#### Choosing the best candidate

All judgement, all `brief.md`, under "Photos". The rules currently in force:

- One that genuinely illustrates **that** story — a generic stock laptop on
  every tech story defeats the point.
- Prefer the largest version available; follow through to the full-size
  original where one exists.
- Never a third-party URL in `imageURL`. The app keeps photos for saved
  articles indefinitely and hotlinks rot, so everything is downloaded and
  self-hosted. (The validator warns rather than fails on an absolute URL,
  because Blob storage is a legitimate future path — but self-hosted is the
  rule.)
- Never pad with a generic image that adds nothing; empty is better.

`photoCandidate.license` is recorded and printed by the fetch step but nothing
enforces it. If Shane wants licensing tightened — say, Wikimedia Commons and
press-office material only — that's a brief rule, and worth pairing with a note
that it will reduce the hit rate.

#### Retention

`photos.retentionDays` (14) drives `prune-images.mjs`, which deletes by the
date prefix in the filename, never by mtime. Anything still referenced by
`docs/latest.json` is kept regardless of age, so the live feed can't point at a
deleted file. Note this is a *repo-size* window, not what Shane sees: the app
keeps 5 days of articles and holds saved photos on the phone indefinitely.

#### Network mechanics are code, not config

Timeout (20s), inter-download delay (1.5s), retry count (4) and backoff (5s)
are constants in `scripts/fetch-photos.mjs`, tuned because Wikimedia
rate-limits unauthenticated bursts and returns 429s that would otherwise fail
most of a batch. A request to change them means editing that file — and if it's
a value Shane will want to tune again, lift it into `config.json → photos`
first and read it through `scripts/config.mjs` like everything else.

### Research effort → `config.json → research`

`maxSearchesPerSection` / `maxSearchesPerRun`. These are honour-system: nothing
checks afterwards. Raise them if sections come back thin; lower them if runs
take too long.

### Sections themselves → careful

`sections.order` drives the validator's category list and the id pattern. But
the five sections are **also hardcoded in the iOS app** at
`NewsApp/Models/NewsCategory.swift` — raw value, display name, sort order, tint
and SF Symbol. Adding, renaming or removing a section needs a Swift change, a
rebuild and a reinstall on Shane's phone, and old articles in the local store
keep the old category. Don't do it as a casual tweak; tell Shane the cost first
and get a yes.

## How to run

1. **Read both files first**, every time — `hermes/config.json` and
   `hermes/brief.md`. They change daily and the values are tuned from
   experience; never edit from memory of a previous session.
2. **Restate the request as the concrete change** before making it: which file,
   which key or paragraph, from what to what. One line, not a plan document.
   If a request is ambiguous in a way that changes the edit ("shorter" — the
   subtitle or the body?), ask. If it's ambiguous in a way that doesn't, pick
   the obvious reading and say which you picked.
3. **Make the edit.** Keep `config.json` valid JSON with its existing shape and
   `_note` comments intact. Keep `brief.md` in its own voice — direct, reasoned,
   explaining *why* a rule exists. A rule with no reason gets ignored on a
   morning when it's inconvenient.
4. **Check consistency.** If a number moved, grep `brief.md` for anywhere it's
   described in prose ("over ~120 characters", ranges spelled out) and make sure
   nothing now contradicts the config.
5. **Verify nothing broke:**
   ```
   node scripts/validate.mjs
   ```
   This re-reads `config.json` and re-checks the *live* feed against the new
   numbers. New failures here are expected and informative — they tell you what
   yesterday's edition would have looked like under the new rules. Report them;
   they are not a reason to revert, and they do **not** mean you should touch
   `docs/latest.json`.
6. **Never regenerate or edit the feed.** This skill changes the instructions,
   not the content. `docs/latest.json` and `docs/archive/*.json` are off limits
   — tomorrow's run produces the result.
7. **Commit** on the current branch with a message naming the behaviour change,
   not the file (`Draw national from El Salto too`, not `Update config.json`).
   Push only if Shane asks.

## Reporting back

Short. For each tweak: what changed, in which file, and what Shane will notice
in tomorrow's edition. Then anything he should know he didn't ask about —
validator warnings the change would have caused on today's feed, a knock-on
that needs an app rebuild, or a request you interpreted rather than confirmed.
