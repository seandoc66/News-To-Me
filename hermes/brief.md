# Daily Feed Brief

**You are reading this as your task for today.** It is the authoritative
instruction set for the run, read fresh each morning. If it contradicts anything
you remember from a previous run, this file wins.

Two companion files, both also current:

| File | What it is |
|---|---|
| `hermes/config.json` | Every tunable setting — locations, sources, word counts, photo limits. The scripts read the same file, so these numbers are what actually gets enforced. |
| `schema.md` | The JSON contract the app decodes. Structure only. |

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

`config.json → sections.storiesPerSection` gives the range to aim for, driven
entirely by what is genuinely newsworthy.

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
- **Prefer `web_extract` on a known source URL** (the outlets in
  `config.json → sources`) over `web_search` — it's direct and doesn't loop.
- If a search repeats a result you've already seen, move on immediately — never
  retry the same query.

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
real and resolve. **Never invent a plausible-looking URL.** Link the *story*, not
the masthead: `https://www.bbc.com/news` is a dead end when tapped. Prefer
primary sources — filings, statements, papers — alongside reporting.

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

**Prefer the largest version available.** A card photo fills roughly 1206 × 1311
physical pixels. Open Graph images are usually 1200 × 630 and fine; list-view
thumbnails are not. Follow through to the full-size original where one exists.
`fetch-photos.mjs` rejects anything below the minimums in `config.json →
photos`, because sips only downsizes — a small source can only be stretched.

### A missing photo never blocks the edition

`imageURL` is **optional**. If there's no suitable photo, or every candidate is
too small, omit the key or set it to `""` and **publish the story anyway**. The
app renders a category-tinted gradient — it looks deliberate, not broken. One
plainer card costs far less than a day with no news.

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
1. Read docs/archive/*.json for the last ~3 days           (avoid repeats)

2. Research and write. Save the draft to
   docs/archive/YYYY-MM-DD.json, with a photoCandidate on each article and a
   `config` block mirroring config.json (see schema.md). Every section in
   sections.order needs an entry there or it disappears from the app's
   Sections screen — the validator warns by name when one is missing.

3. Fetch and resize photos:
      node scripts/fetch-photos.mjs docs/archive/YYYY-MM-DD.json
   Re-running only retries what is still missing.

   Non-zero exit means some photo failed. Make ONE reasonable attempt at
   replacements, then move on — set their imageURL to "" and continue.

   Confirm the JSON matches what is actually on disk before continuing.
   A photo can download successfully and still have its path not written
   back, which reads as a missing photo when the file is right there.

4. Validate:
      node scripts/validate.mjs docs/archive/YYYY-MM-DD.json

5. FAILS  → stop. Do NOT touch docs/latest.json. Report the errors.
   PASSES → read the warnings anyway, then publish:
      cp docs/archive/YYYY-MM-DD.json docs/latest.json

6. Prune old photos:
      node scripts/prune-images.mjs

7. Final check against the live file:
      node scripts/validate.mjs

8. Commit and push to main. GitHub Pages deploys automatically.
```

### Warnings are the quality signal

They never block publication, and four are worth acting on every run:

- **`… cite the same source … same story published twice`** — the duplicate
  check. Reworded headlines defeat any headline comparison, so this is what
  actually catches it. Treat it as a duplicate until you've shown otherwise.
- **`… is a section or home page … dead end when tapped`** — link the story.
- **`… publishing without a photo`** — informational, tells you whether the photo
  step is degrading.
- **`… paragraph N is … words`** / **`… subhead(s) in a … story`** — the body
  shape. Both are cheap to fix by re-breaking the prose, and both are exactly
  what the reader feels.

---

## Report each run

Your report is the only account of what happened. The watchdog can say *that*
something is wrong; only you can say *what*.

State plainly:

- Whether the edition **published**, and if not, why.
- Any story that shipped **without a photo**.
- Any **validator warnings**, especially duplicates and dead-end links.
- Anything that looked wrong that you worked around.

**Check the report against the files before sending it.** A report that
disagrees with the repo sends whoever reads it after the wrong problem.

If something needs changing on the app side — a contract change, a new field —
say so explicitly rather than assuming it will be noticed.

---

## If validation fails

Leave the previous day's `latest.json` in place and report. Yesterday's feed
staying live beats a broken or empty one.

Be aware that a stale feed is now visible: the app shows a banner past 26 hours,
and a watchdog emails Shane each morning if no fresh edition arrived. Silence is
no longer the failure mode — but neither of those explains *why*, which is what
your report is for.
