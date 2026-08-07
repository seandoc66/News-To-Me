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

The one setting that can't live there is the app's **5-day article retention**,
which is compiled into the app. Changing it needs a rebuild and reinstall. It is
tied to the five buttons on the front page — a story older than the oldest button
has nowhere left to be read, so the two numbers are one number.

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
   refresh and shows a banner past 26 hours. It sits inline on the front page,
   under the masthead — the screen you land on, and the one where today's button
   is visibly empty. That threshold clears the daily
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

## Reading a day

The app opens on a front page: the masthead, and a button for each of the last
five days named after its weekday. Picking one slides that day's edition in from
the right; the story pager and the full story sit behind it, as before.

Each button's background is a collage of four photos sampled evenly across that
day's stories — evenly rather than off the front, because the store is ordered by
section and the first four photos of any edition are always the same section.

**Colour is the progress bar.** A day you haven't opened is in full colour; one
you've read every story of is greyscale; part-read lands proportionally between.
A story counts as read when its full text is opened, and only the first visit
counts. The badge on each button says the same thing in words — saturation alone
would be a signal carried entirely by colour, which is no signal at all to a
colour-blind reader or to VoiceOver.

**One day at a time, never all of them.** The feed used to page through
everything the store held, so the story after the last of today's was yesterday's
lead and nothing marked the join. Days are the unit news arrives in, so they are
the unit you choose between.

**Backfilled from the archive, but only into gaps.** The app still fetches only
`latest.json`; a past day is otherwise populated only if the app happened to be
opened that morning, which would leave a fresh install showing four empty
buttons. Days with no stories at all are filled from `docs/archive/`. Days that
already have stories are left alone — editions overlap, and re-stamping a story
today's feed has already claimed would drag it back onto an older button.
Backfilled stories are dated to their edition, not to now, so a four-day-old
edition doesn't outlive its own button by four days.

---

## How it looks

Three choices, on the sheet behind the slider button, saved on the phone and
nowhere else — the feed has no say in any of them. They default to what the app
was before they existed: dark, serif, and the phone's own text size.

**Theme — system, light or dark.** The app was black-and-white by construction:
`.background(.black)` and `.foregroundStyle(.white)` written in at every call
site, because dark was the only mode. Both are now named for their job instead of
their colour — `Palette.page` is the paper, `Palette.ink` is what's printed on
it — and flip together. Not every black became a page: the scrim under a
headline, the shadow a turning page casts and the section tag's own white
lettering sit on a photograph rather than on the page, so they stay put in both
modes. Section tints have a second, darker set for light mode; the first was
picked to sit on black, and the reading bar names the current section in flat
tint on the page itself.

**Reading font — serif, sans or rounded.** A `Font.Design`, not a bundled
typeface, so every weight and every Dynamic Type size keeps working. It governs
headlines, subheads and story text. Two things stay where they are: the masthead,
which is a wordmark rather than something you read, and the teaser under the
headline on each card, which is the standfirst to a display line — the contrast
between the two faces is the point, and matching them makes the card one
undifferentiated block of type.

**Text size — a step, not a size.** Small through X-Large move one or two places
along the Dynamic Type scale *from wherever the phone is already set*, so
someone who reads large everywhere keeps it. Worked out once at the root, in
`themed(_:)`, which is the only place that still sees the phone's own setting
before the app's step goes on top.

Sheets need both restating (`themedSheet()`). A sheet is its own UIKit
presentation: custom environment values reach it, but `preferredColorScheme`
travels the other way, and the type size gets re-read from the phone's trait. The
step is handed on as a finished size so restating it can't compound it.

---

## Decisions worth remembering

**A JSON file, not SwiftData.** ~200 records, no relationships, no queries beyond
a sort. A file is less code, has no schema migration to get wrong, and can be
`cat`-ed when debugging. A SwiftData migration mismatch that stopped the app
launching would be miserable to diagnose on a phone.

**Every dynamic colour's provider is `nonisolated`.** `Palette.page`,
`Palette.ink` and `NewsCategory.tint` are all `UIColor(dynamicProvider:)`, and
UIKit runs that closure on whichever thread is drawing. A settled screen draws on
the main thread; a page turn drives its frames from SwiftUI's own async render
thread. The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
infers those closures `@MainActor`, and Swift 6 guards a main-actor closure
reached through a non-isolated function type with a main-queue assertion — so
every single swipe trapped in `ShapeStyleResolver` on the render thread. Nothing
in a colour provider needs the main actor. Any new dynamic colour needs the same
annotation.

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
Markdown in it still renders — as one paragraph — so the five days of plain-prose
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

**The card is positioned against the window, not against its container.** Once
the feed became a *pushed* screen with its nav bar hidden, the numbers around it
stopped agreeing: it is laid out from an origin 20pt down the screen while
reporting a 47pt top inset, so `ignoresSafeArea` — and anything else derived from
that pair — put the card 27pt too high and the section tag level with the clock.
`FeedView` now sizes the card to the window and pulls it up by the reader's
measured global origin. Related: the card's lower half is given an exact height
and its two `Text`s are no longer `fixedSize`, because pinning a `Text` to its
ideal height silently cancels the `minimumScaleFactor` under it — which is how a
long headline used to grow the card past the screen and push the heart off it.

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

- **The 5-day purge has never been tested against backdated data.** It has
  shipped to the phone unverified, and silently losing a saved article is the
  worst bug this app could have.
- **The fold animation's angle and perspective are initial guesses**, tuned by
  eye rather than measured.
- **The app can't write anything back.** The `config` block in the feed is shown
  read-only. Letting Shane edit sources or story counts from the phone would need
  a return path that doesn't exist.
- **No tests.** If anything deserves one it is `merge` / `purgeExpired` in
  `ArticleStore`.
