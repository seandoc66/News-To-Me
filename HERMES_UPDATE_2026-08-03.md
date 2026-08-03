# Update for Hermes — 3 August 2026

## The change: a missing photo no longer blocks the feed

Today's edition was written, researched and correct — sixteen stories across all
five sections — and it did not reach the phone, because two of them had no
picture. That trade is wrong, so the rule has changed.

**`imageURL` is now optional.** If a story has no photo, omit the key or set it
to `""` and **publish the story anyway.**

You were right not to publish under the old rules. The rules were wrong, not your
handling of them. This update fixes the rule.

### Why this is safe

The app has always rendered a category-tinted gradient for photos that fail to
load — it was built as a fallback for exactly this. A card without a photo looks
deliberate rather than broken. `Article.imageURL` is now optional in the app, so
absent, `null`, and `""` all mean "no photo" and render that fallback.

The old requirement made the contract stricter than the app ever needed.

### What is still an error

Two things fail validation, because they mean something is broken rather than
merely unavailable:

| Condition | Why |
|---|---|
| `imageURL` points at a file not on disk | Absent is fine; a broken path is a bug. |
| More than half the batch has no photo | That's the photo step having failed, not a run of bad luck. Worth stopping for. |

Everything else about photos is unchanged: still self-hosted, still resized to
1000px/quality 75, still pruned on a rolling 14-day window. Don't pad with a
generic image that adds nothing — an empty `imageURL` is the better outcome. And
don't drop an interesting story just because it has no picture. Publish it.

---

## Today's feed is still unpublished — and two things in your report were wrong

`docs/archive/2026-08-03.json` now **passes validation** under the new rules. It
has not been published; that's yours to run.

Before you do, three things worth knowing, because two of them point at a bug in
the run rather than in the news.

### 1. The report named the wrong story

Your report says `2026-08-03-tech-003` (Seedance 2.5) needs a photo. It doesn't —
`tech-003` has one, 95KB, on disk, with `imageURL` set correctly.

The article with an empty `imageURL` is **`2026-08-03-tech-002`, the Go 1.27
story**. Acting on the report as written would have meant hunting for a Seedance
image, fixing nothing, and staying blocked.

### 2. One of the two "missing photos" isn't missing

`docs/images/2026-08-03-tech-002.jpg` **exists**, 62KB. The download worked. The
path was simply never written back into the article JSON.

So of the two blockers, only **`ai-002` (EU AI Act)** genuinely has no photo.

Taken with the misnaming above, this suggests your in-run state drifted from what
was actually on disk. **Worth checking whether articles get renumbered mid-run**,
because `id` is load-bearing: the app tracks Shane's saved stories by it, and an
id shifting between what you think you wrote and what lands on disk could detach a
saved article from its story. Probably harmless here, but confirm it isn't
systematic.

Since the file is already there, `tech-002` just needs
`"imageURL": "/images/2026-08-03-tech-002.jpg"`. Only `ai-002` needs a decision:
find a photo, or publish it without one.

### 3. The same story ran twice

`tech-001` and `ai-001` are both OpenAI's Astra model solving ten open maths
problems. Same four sources, and byte-identical images:

```
9125b70ea5c57ee24f85a1c9b7eb58b7   2026-08-03-tech-001.jpg
9125b70ea5c57ee24f85a1c9b7eb58b7   2026-08-03-ai-001.jpg
```

The headlines are reworded, so the exact-match headline check never saw it. This
would have shipped, and Shane would have swiped the same story twice in one
edition — the failure the brief calls the most irritating possible one in a feed
read once a day.

`tech` and `ai` overlap by nature, so this will recur. **Merge or drop one before
publishing.**

---

## New validator warnings

Warnings never block publication. Three are worth acting on every run:

- **`… cite the same source … check these aren't the same story published twice`**
  Catches the case above. Only fires on deep links, not mastheads, so a shared
  `bbc.com/news` won't trip it.
- **`… is a section or home page …, it's a dead end when tapped`**
  Four of today's global stories cite `https://www.bbc.com/news`. Shane taps that
  expecting the story and gets a masthead. Link the article itself.
- **`… article(s) publishing without a photo`**
  Informational, so a glance tells you whether the photo step is degrading.

---

## One thing to fix that isn't about photos

**Nobody told Shane the feed hadn't published.** He found out days later by
asking. A silent non-publish is indistinguishable from a quiet news day, and the
feed had been stale since the 2nd.

Your report was clear and honest — it just sat there. Whatever alerting you can
reach, an abort should actively reach Shane rather than wait to be read. This
matters more than any single missing image: under the new rules a photo failure
won't stop the feed, but the failures that *do* stop it will still be invisible
unless something says so.

---

## To publish today

```
# fix tech-002's imageURL, decide on ai-002, resolve the tech-001/ai-001 duplicate
node scripts/validate.mjs docs/archive/2026-08-03.json
cp docs/archive/2026-08-03.json docs/latest.json
node scripts/prune-images.mjs
node scripts/validate.mjs
git add -A && git commit -m "Daily feed: 2026-08-03" && git push origin main
```

The standing brief in `HERMES_HANDOFF.md` has been updated to match all of the
above — sections 5, 7 and 8. This file is just the changelog; that one remains
the source of truth.
