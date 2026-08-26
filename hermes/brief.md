# Daily Feed Brief

**You are reading this as your task for today.** It is the authoritative
instruction set for the run, read fresh each morning. If it contradicts anything
you remember from a previous run, this file wins.

Two companion files, both also current:

| File | What it is |
|---|---|
| `hermes/config.json` | Every tunable setting — locations, sources, word counts, photo limits. The scripts read the same file, so these numbers are what actually gets enforced. |
| `schema.md` | The JSON contract the app decodes. Structure only. |
| `hermes/report-schema.md` | The JSON contract for the run report you write at the end — see "Report each run" below. |

Working directory is the repo root: `/Users/shanedoc/Sites/News-To-Me`

---

## Your task

Produce one edition of a personal news feed and publish it.

Six sections, in this order, from `config.json → sections.order`:

```
local → national → northernIreland → global → tech → ai
```

`local`, `national` and `northernIreland` mean the places in
`config.json → locale`. Lugo and Spain are where Shane lives; Northern Ireland is
where he's from, and it gets a section of its own rather than waiting for the
days the rest of the world happens to notice it. Within that section the
north-west — Strabane, Derry, Tyrone — carries more weight than a Belfast story
of the same size.

**What language to write in.** `config.json → locale.outputLanguage` is keyed by
section, with `default` covering the ones it doesn't name. Read it rather than
assuming; today it puts `local` and `national` in Spanish and the rest in
English. That is the point of the setting: those stories are nearly all
translations of Spanish reporting, and a translation puts another layer of
paraphrase between Shane and what was actually said. Quotes especially should
reach him in the words they were spoken in.

**Read in any language; write in the section's.** The two never constrain each
other. Most Lugo coverage is in Spanish or Galician and most Northern Irish
coverage is in English; restricting yourself to sources in the output language
would gut both sections. The language covers `headline`, `subtitle` and `body`
only — leave `sources[].name` as the outlet calls itself. A mixed-language
edition is the expected result, not a fault.

`config.json → sources` lists the outlets Shane expects each section to draw on.
They are starting points, not a closed list. Follow a story wherever it leads.

The Northern Ireland list is doing a second job. The Belfast Telegraph, The Irish
News and the News Letter report the same events from settled and different
political positions, and all three are on it deliberately. Where they diverge on
a contested story, say who is claiming what — quietly picking the version that
reads most smoothly is how a feed acquires a line of its own without anyone
deciding to give it one.

### How many

`config.json → sections.storiesPerSection` gives the range to aim for, keyed by
section like `locale.outputLanguage` — `default` covers any section not named.
Local and Northern Ireland run narrower (1–3) than the rest; AI runs wider
(4–6). Read the current values per section rather than assuming a single range
applies everywhere. Driven entirely by what is genuinely newsworthy.

**Never pad to hit a number.** A quiet local day that yields two real stories is
a correct outcome; five padded non-stories is a failure. If something big is
unfolding, exceeding the range is fine. An empty section is a warning, not an
error — deliberately.

### Researching without looping

The failure mode here is searching in circles, not searching too little. Hard
caps, from `config.json → research`:

- **`maxSearchesPerSection` `web_search` calls per section.** Once you hit it,
  stop researching that section and write with what you have.
- **`maxSearchesPerRun` `web_search` calls across the whole run.**
- If a search repeats a result you've already seen, move on immediately — never
  retry the same query.

These caps are on `web_search` specifically. RSS fetches and `web_extract`
calls don't count against them, which is exactly why the order below leans on
them first.

**Research each section in this order:**

1. **RSS first, where an outlet has one.** `config.json → sources` gives each
   outlet an `rss` field where a real feed exists. Fetch it directly (`curl` via
   the terminal tool — this is a plain HTTP request, free, and doesn't touch
   your search caps) and skim the entries for anything from the last day or two
   worth a story. A feed only gets you headlines/links, not full text — you
   still `web_extract` each article you're actually considering, exactly as
   before, both for the body and because the photo comes from that same page
   (see "Photos" below). RSS replaces `web_search` for *discovery* only; it
   changes nothing else about how a story gets written or photographed.
2. **`web_extract` on a known source URL** for anything RSS didn't surface but
   you already know is worth checking (a specific press release, a follow-up on
   yesterday's story) — direct and doesn't loop.
3. **`web_search`, spending from the caps above**, only for what's left: an
   outlet with no `rss` field, a story you know is happening that isn't in any
   feed yet, or verifying/expanding a contested claim.

Read the current values from the config rather than assuming — they are tuned
from experience and will change.

Nothing checks afterwards whether you respected these; they hold only because you
follow them. Hitting a cap with a thin section is fine: a genuinely empty section
is a correct outcome (see above), not a reason to keep searching.

---

## Writing each story

**Headline** — short, factual, headline style, no trailing period. Over ~120
characters wraps awkwardly on the phone.

**Subtitle** — length from `config.json → writing.subtitleWords`. This is what
Shane reads on the card to decide whether to open the story, and most stories
are only ever read at this length. It must *add* information the headline
doesn't carry. Never a reworded headline.

**Body** — length from `config.json → writing.bodyWords`. *Match the length to
the story.* A council decision may be complete at the low end; a shifting
geopolitical situation may genuinely need the top of the range. Never inflate
with scene-setting or "it remains to be seen" filler to reach a count.

Clear, neutral, factual reporting. **Rewrite and synthesise — never copy
sentences verbatim from any outlet.** Where sources disagree, say so briefly
rather than silently picking one. Be sceptical of vendor and press-release
claims; attribute contested figures to whoever claimed them.

### Shaping the body

The body is **Markdown**, in a deliberately small subset. Structure it like a
news story, not like a memo:

```markdown
Opening paragraph. This is the lede: what happened, before anything explains
it. It is the only part many stories get read past.

Second paragraph, developing it.

## A subhead, if the story has earned one

The part the subhead announced.
```

That is the whole subset: **blank lines between paragraphs**, `## ` subheads,
and `**bold**` / `*italic*` used sparingly. **No `#`** — the headline owns that
level. No lists, no links, no images, no blockquotes, no tables. Sources go in
`sources`, never as links in the prose.

**Paragraphs**: `config.json → writing.paragraphWords`. On a phone a paragraph
over that maximum is a wall of text. Break where the story turns, not every N
words — a paragraph is a unit of thought, and one deliberately short line lands
hard when the rest are full.

**Subheads are the exception, not the furniture.** Only consider one above
`config.json → writing.subheadsAboveWords` words of prose, and only where a long
story genuinely changes subject — the numbers behind a decision, the reaction to
it, what happens next. Most stories are shorter than that and want none at all;
two or three paragraphs and no subhead is a complete, well-formed story. A short
story chopped into labelled parts reads worse than the same story left whole.

Never open on a subhead — the headline already did that job — and never end on
one with nothing underneath.

Subhead text doesn't count toward `bodyWords`. Adding subheads doesn't buy you
room, and it doesn't cost you any either.

**Sources** — count from `config.json → writing.sourcesPerArticle`. These are
the places you actually researched from, and Shane taps them. Every URL must be
real, resolve, and land on *that specific story* — never a masthead, a
homepage, or a section/category front (`https://www.bbc.com/news`,
`https://techcrunch.com/category/artificial-intelligence/`), even when that's
the only page you actually had open. **Never invent a plausible-looking URL.**
If the only thing you looked at for an outlet was its homepage or a roundup
page, that outlet doesn't have a citable source for this story yet — either
find its actual article or cite a different outlet whose specific article you
do have. A story-specific link at a less-obvious outlet beats a dead end at
the expected one.

This is not a style preference: `validate.mjs` rejects a section/homepage URL
outright and the run **fails**, the same as a photo file that doesn't exist on
disk. It used to only warn, and a full edition went out with roughly half its
links landing on homepages before anyone noticed — a warning that's cheap to
ignore on a Friday evening doesn't get read. Prefer primary sources — filings,
statements, papers — alongside reporting.

### One story, once

**A story appears in exactly one section, once per edition.** This is the rule
most often broken, because sections genuinely overlap:

| Overlap | Goes in |
|---|---|
| An AI model, lab, or AI policy story | `ai` — never also `tech` |
| A Spanish story with an international dimension | `national` |
| An international story that Spanish outlets also cover, but that isn't fundamentally about Spain | `global` |
| A Lugo or Galicia story that reached the national press | `local` |
| A Northern Ireland story the national or world press picked up | `northernIreland` |
| A Westminster, Dublin or all-Ireland story with a real NI angle | `northernIreland` — without one, `global` |
| A tech story that is mostly EU or Spanish regulation | one section, whichever Shane would look in |

**The closer, more specific section wins.** When torn, pick one and drop the
other — never hedge by running both.

**National vs. global is decided by what the story is *about*, not by who's
covering it.** A crisis centred on Spanish territory or Spanish policy — a
migration surge at Ceuta, a national election, a Spanish court ruling — is
`national` even once the world press picks it up too, per the row above. A
story that would be global news regardless of Spain's involvement — a
shipping-lane crisis, a war, a pandemic — stays `global` even though the
Spanish outlets in `sources.national` are also reporting it, because that's
where Shane would look for it first. Either way, write it once, from
whichever section's sources give the fuller picture, and don't split the
same story's coverage across both.

Cross-posting is defensible only when the two pieces are genuinely different
stories touching the same subject: different angle, different facts, **different
sources**. If they share a source URL, they are the same story.

### Don't repeat recent days

Read the last few days of `docs/archive/*.json` before writing. A developing
story may be revisited, but only with a new angle and a headline that makes the
development clear.

---

## Photos

**One photo per story, hosted by us.** Never put a third-party URL in
`imageURL` — the app keeps photos for saved articles indefinitely, and hotlinks
rot.

The app crops that single file to fill the top half of the card and shows the
same file, smaller, in the header when the story is opened. **Don't supply
separate images for the two, and don't change the shape of what you provide.**

Give every story a photo where you reasonably can. Choose one that genuinely
illustrates *that* story — a generic stock laptop on every tech story defeats
the point. Shane cares about the photos.

**The photo comes from a source you already cited, not a separate search.**
`sources[]` are the article pages you actually researched from — you were just
on them. Take the photo the outlet itself published with that story: its Open
Graph image, or a specific photo from the body if the og:image is a generic
site banner. Work through `sources[]` in order until one has a usable
article-specific photo. **Never substitute an image from anywhere else** —
a stock photo, an illustrative library shot, an image from an unrelated
article — even one that is technically a good, sharp, on-topic-looking photo.
If it didn't come from the story you're citing, it isn't *that* story's photo,
and a reader who opens the source will notice it doesn't match. This is the
same rule as never inventing a source URL, applied to the picture: real and
traceable to the story, or omitted.

**Prefer the largest version available.** A card photo fills roughly 1206 × 1311
physical pixels. Open Graph images are usually 1200 × 630 and fine; list-view
thumbnails are not. Follow through to the full-size original where one exists.
`fetch-photos.mjs` rejects anything below the minimums in `config.json →
photos`, because sips only downsizes — a small source can only be stretched.
That threshold is a size check, not a relevance check — it will happily accept
a sharp, correctly-sized photo of the wrong thing, so it's not a substitute for
sourcing the photo correctly in the first place.

### A missing photo never blocks the edition

`imageURL` is **optional**. If none of `sources[]` has a usable photo, or every
candidate is too small, omit the key or set it to `""` and **publish the story
anyway**. The app renders a category-tinted gradient — it looks deliberate,
not broken. One plainer card costs far less than a day with no news.

Never pad with a generic image that adds nothing; an empty `imageURL` is better.
And never drop an interesting story merely because it has no picture.

Two things *are* still errors, because they mean something is broken rather than
unavailable:

- An `imageURL` pointing at a file that isn't on disk. Absent is fine, broken is not.
- More than half the batch missing photos — that's the photo step having failed.

---

## The run

All commands from the repo root.

```
0. Check whether today already has work in progress, before assuming a clean
   start:
     - docs/archive/YYYY-MM-DD.json already exists → skip straight to step 4
       (publish). Don't redo finished research.
     - drafts/YYYY-MM-DD/ has some section files but no archive yet → a
       previous attempt today ran out of budget partway. Skip research for
       every section that already has a draft file and resume from the next
       one in sections.order, then continue to step 3.
     - Neither exists → normal run, start at step 1.

1. Read docs/archive/*.json for the last ~3 days           (avoid repeats)

2. Research and write ONE SECTION AT A TIME, saving each before starting the
   next:
      drafts/YYYY-MM-DD/local.json
      drafts/YYYY-MM-DD/national.json
      ... one file per section in sections.order

   Each file holds only that section, with a photoCandidate on each article:

      { "sources": [ { "name": "El Progreso", "url": "https://..." } ],
        "articles": [ ... ] }

   `sources` are the outlets this section actually drew on today. Article
   order within the file is the running order the app shows — most
   significant first.

   Do NOT write the whole edition in one go. See "Why section by section".

   **Watch your remaining budget, not just the research caps.** A published
   edition from five finished sections beats a six-section edition that's
   fully researched but never shipped — that has happened before (see "Why
   section by section"). If you can tell you're running low — several
   compactions already, or you're deep into a section with two or three still
   to go — stop researching the rest, write up what you have as one more
   thin-but-real section (or leave it genuinely empty per "How many"), and go
   straight to steps 3–5. Merging and publishing what's done is always worth
   more than researching a section you won't get to write.

3. Assemble the edition:
      node scripts/merge-sections.mjs YYYY-MM-DD

   Writes docs/archive/YYYY-MM-DD.json, adding `generatedAt` and the `config`
   block itself from config.json — don't write those by hand. A missing
   section warns and comes out empty; it fails on a bad id, a duplicate id,
   or a story filed under the wrong section.

4. Publish everything in one shot (photo-fetch → validate → copy → prune →
   final validate → git add/commit/push):
      node scripts/publish-and-push.mjs docs/archive/YYYY-MM-DD.json

   This script handles all mechanical steps and exits with a clear code:
     0 = published and pushed
     1 = validation FAILED (edition NOT published — do NOT touch latest.json)
     2 = post-validation step (cp/prune/git) failed — investigate

   If it fails, read the output. Most validation failures are a specific,
   mechanical fix — make it and re-run the script, up to twice more:
     - A body or paragraph over its word cap by a small margin: tighten the
       prose (cut a redundant clause, not a fact) rather than rewriting the
       story.
     - A headline over the character guideline, or a source/photo issue
       `publish-and-push.mjs` names specifically: fix that one thing.
   If the same error repeats after a genuine fix attempt, or the failure isn't
   a specific content shape issue (a tool erroring, a script crashing, a whole
   section missing) — stop retrying. Write the report with `needsHumanAttention`
   and move on; guessing at an unrelated fix costs budget without helping.
   To retry a specific sub-step (e.g. retry failed photos) run individual
   commands manually, then re-run publish-and-push.mjs to finish.

5. Either way, write hermes/reports/YYYY-MM-DD.json (hermes/report-schema.md)
   and commit and push it — this is not something publish-and-push.mjs does
   for you:
     exit 0 → published: true.
     exit 1 → published: false, with the validator errors it printed. The
       script already left docs/latest.json untouched; just write the report.
     exit 2 → whatever you find after investigating — validation passed but
       something mechanical broke, so this is closer to the "needs a human"
       end of hermes/report-schema.md than an ordinary run.
```

### Why section by section

An edition is 45–67KB of JSON. Written in one go it sits inside a single
response, and that has already cost entire runs — an August 2026 run failed
with the write truncated mid-response, and two later runs never got past
research at all because the single-file write was the last big step standing
between finished research and a published edition, and there wasn't enough
of the run's tool-call budget left to reach it. Each failure left nothing on
disk: no draft, no report, no day.

Six files of roughly 4–14KB each mean a truncated or budget-cut write costs
one section rather than the edition. Everything already written is on disk
and still good, so a re-run only has to redo the section that failed — check
`drafts/` before assuming you're starting from nothing.

`drafts/` is scratch space and isn't committed. `docs/archive/YYYY-MM-DD.json`
remains the edition of record, and steps 4 onward are unchanged — they still
operate on that one assembled file.

**If a section is genuinely too long to write in one file**, it's too long for
the edition — that's the story-count guidance in "How many" telling you
something, not a reason to split further.

### Warnings are the quality signal

They never block publication, and three are worth acting on every run:

- **`… cite the same source … same story published twice`** — the duplicate
  check. Reworded headlines defeat any headline comparison, so this is what
  actually catches it. Treat it as a duplicate until you've shown otherwise.
- **`… publishing without a photo`** — informational, tells you whether the photo
  step is degrading.
- **`… paragraph N is … words`** / **`… subhead(s) in a … story`** — the body
  shape. Both are cheap to fix by re-breaking the prose, and both are exactly
  what the reader feels.

A section-or-homepage source URL is **not** in this list anymore — it's a hard
failure now (see "Sources" above), not a warning to weigh.

---

## Report each run

Your report is the only account of what happened. The watchdog can say *that*
something is wrong; only you can say *what*. Write it twice, in two forms,
every run — including a run that fails validation:

1. **Prose**, wherever you'd normally send it. State plainly:
   - Whether the edition **published**, and if not, why.
   - Any story that shipped **without a photo**.
   - Any **validator warnings**, especially duplicates and dead-end links.
   - Anything that looked wrong that you worked around.
2. **`hermes/reports/YYYY-MM-DD.json`**, following `hermes/report-schema.md`.
   Commit and push it — same commit as the edition if you published, its own
   commit if you didn't. Nothing else in the repo reads it; it exists so an
   hourly check can tell, without you, whether today's run needs a human.

**Check the report against the files before sending it**, in both forms. A
report that disagrees with the repo sends whoever reads it after the wrong
problem.

If something needs changing on the app side — a contract change, a new field —
say so explicitly rather than assuming it will be noticed.

---

## If validation fails

Leave the previous day's `latest.json` in place — yesterday's feed staying
live beats a broken or empty one — but still write and commit both reports
above. `published: false` with a real `validatorErrors` list in the JSON
report is what turns "nothing happened" into "something specific broke,"
which is the whole reason that file exists. Do not skip the commit just
because there's nothing to publish.

Be aware that a stale feed is now visible: the app shows a banner past 26 hours,
and a watchdog emails Shane each morning if no fresh edition arrived. Silence is
no longer the failure mode — but neither of those explains *why*, which is what
your report is for.
