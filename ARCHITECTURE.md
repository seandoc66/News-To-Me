# News-To-Me — how it fits together

A personal daily news app. Hermes researches and writes an edition each morning
and publishes it as static JSON; an iOS app on Shane's phone reads it.

**This document is for humans.** It is not read by the daily job — see
[`hermes/brief.md`](hermes/brief.md) for that.

---

## The pieces

```
hermes/
  brief.md          the daily prompt — read by the cron each morning at 06:00
  config.json       every tunable setting; the scripts read this too
schema.md           the JSON contract the app decodes
scripts/
  config.mjs        loads config.json for the other scripts
  validate.mjs      hard-fails a batch that breaks the contract
  fetch-photos.mjs  downloads, size-checks and resizes photos
  prune-images.mjs  enforces the rolling photo window
docs/               what GitHub Pages serves
  latest.json         the live edition
  archive/            every edition, by date
  images/             photos, named by article id
NewsApp/            the iOS app
.github/workflows/
  feed-watchdog.yml daily check that a fresh edition actually landed
```

### Who reads what

| File | Hermes, daily | Scripts | App | Human |
|---|:--:|:--:|:--:|:--:|
| `hermes/brief.md` | ● | | | ● |
| `hermes/config.json` | ● | ● | | ● |
| `schema.md` | ● | | | ● |
| `ARCHITECTURE.md` | | | | ● |

`config.json` matters most here. Every tunable number — word counts, source
counts, photo dimensions, retention — lives there and nowhere else. Before, the
same values sat in prose *and* in each script, so editing the document that
looked authoritative changed nothing and caused validation failures that pointed
at the wrong culprit.

The one setting that can't live there is the app's **7-day article retention**,
which is compiled into the app. Changing it needs a rebuild and reinstall.

---

## Publishing

GitHub Pages, serving `docs/` on `main`. Live at
`https://seandoc66.github.io/News-To-Me/`, with `latest.json` at the root and
photos under `/images/`. Publishing is `git push`; Pages deploys automatically.
`latest.json` is served `max-age=600`.

The repo is public. Nothing here is worth protecting, and a public repo is what
makes Pages free and the app's fetch trivial — no tokens, no auth in the client.

---

## How failure surfaces

A feed that fails to publish used to be invisible. On 3 August a batch correctly
refused to publish, the previous day's file stayed live, and it went unnoticed
for two days: the app showed a full screen of real stories and said nothing,
because the fetch had succeeded. A stale feed and a quiet news day looked
identical.

Three things now cover it, at different distances:

1. **Hermes' own report** — the only thing that can say *why*.
2. **The app** compares the edition's `generatedAt` against the clock on every
   refresh and shows a banner past 26 hours. That threshold clears the daily
   peak — a feed is normally hours old and briefly approaches 24 just before the
   next run — without hiding a real miss for long. It runs whether or not the
   fetch succeeded, because a successful fetch of yesterday's feed is exactly
   the case that was silent.
3. **A GitHub Actions watchdog** fetches the published URL each morning and
   fails if the edition is over 24 hours old, unreachable, or empty. GitHub
   emails on a failed scheduled workflow.

The watchdog checks the live URL rather than the repo, so it exercises the Pages
deploy too, and it is deliberately independent of Hermes: Hermes can report its
own aborts but cannot report never having run, which is the failure most likely
to pass unnoticed.

---

## Decisions worth remembering

**A JSON file, not SwiftData.** ~200 records, no relationships, no queries beyond
a sort. A file is less code, has no schema migration to get wrong, and can be
`cat`-ed when debugging. A SwiftData migration mismatch that stopped the app
launching would be miserable to diagnose on a phone.

**A custom image cache, not `AsyncImage`.** `AsyncImage` does no caching, so
paging back would refetch every photo. The cache also downsamples at decode
time, which matters because rotating full-resolution JPEGs in 3D during the fold
is the most expensive thing the app does. Photos are kept on disk so a saved
article still has its picture months later.

**The body is a Markdown *subset*, not Markdown.** Paragraphs, `## ` subheads,
inline emphasis — that is all the app parses. Bodies used to be one unbroken
string, which on a phone is a wall of serif text with no way in. Full Markdown
would have meant carrying a renderer for lists, tables, code and links that a
300-word news story will never use, and every unused construct is a way for the
generator and the app to disagree about what the reader sees. The subset is small
enough that `StoryBlock.parse` and the validator's `parseBlocks` are the same
twenty lines written twice, which is what keeps them honest. A body with no
Markdown in it still renders — as one paragraph — so the week of plain-prose
stories already on the phone didn't need migrating.

**Photos self-hosted, on a rolling window.** Hotlinks rot, and a saved story with
a dead image is exactly the failure Shane would hate. The window keeps git from
growing without bound — deleted blobs stay in history forever, so without it the
repo grows a couple of GB a year.

**`imageURL` is optional.** Requiring a photo made the contract stricter than the
app needed: the app has always had a category-tinted fallback. On 3 August one
missing image held back a complete, correct edition of sixteen stories for a
whole day. One plainer card is a far better trade.

**Photos resize to 1600px, not 1000px.** A card photo fills about 1206 × 1311
physical pixels. The old 1000px ceiling guaranteed roughly 2.3× upscaling on
every photo, which is what made them look soft and, on smaller sources, visibly
pixelated. Sources below 800 × 450 are now rejected outright — sips only
downsizes, so a small source can only be stretched.

**Purge runs on every launch, independent of the network.** Otherwise a week
offline would mean nothing ever expires. Saved articles are exempt.

**Navigation carries article ids, not `Article` values.** Hearting a story mutates
`savedAt`, which changes the value's hash and would break navigation identity
mid-read.

**Duplicate detection keys on source URLs, not headlines.** Sections overlap —
`tech` and `ai` especially — and a reworded headline defeats string comparison.
Two articles citing the same *story* URL are almost always one story written
twice. It only fires on deep links, since a shared masthead like `bbc.com/news`
is cited legitimately by unrelated stories.

**The deployment target is iOS 18, not 26.** Shane's phone is an iPhone SE (3rd
generation) on iOS 18.6.2. `GlassCompat.swift` routes the Liquid Glass calls
through `#available` and falls back to a frosted material below iOS 26. Nothing
depends on glass structurally — every call site is decoration floating over a
photo.

---

## Known gaps

- **The 7-day purge has never been tested against backdated data.** It has
  shipped to the phone unverified, and silently losing a saved article is the
  worst bug this app could have.
- **The fold animation's angle and perspective are initial guesses**, tuned by
  eye rather than measured.
- **The app can't write anything back.** The `config` block in the feed is shown
  read-only. Letting Shane edit sources or story counts from the phone would need
  a return path that doesn't exist.
- **No tests.** If anything deserves one it is `merge` / `purgeExpired` in
  `ArticleStore`.
