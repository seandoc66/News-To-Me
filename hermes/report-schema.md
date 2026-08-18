# Run Report Contract

This is the contract between Hermes and whatever reads its run report — a
human, or the hourly check described in `ARCHITECTURE.md`. It is written
**every run, whether the edition published or not**, to
`hermes/reports/YYYY-MM-DD.json`. Unlike the feed itself, nothing on the phone
ever reads this file; it exists purely so a run's outcome survives past
whatever produced it.

This is a companion to the prose report `hermes/brief.md` already asks for
under "Report each run" — write both. The prose is for a human reading
top-to-bottom; this file is for something deciding, unattended, whether to
act.

## File: `hermes/reports/YYYY-MM-DD.json`

```json
{
  "date": "2026-08-14",
  "published": false,
  "publishedAt": null,
  "sections": {
    "present": ["local", "national"],
    "missing": ["northernIreland", "global", "tech", "ai"]
  },
  "storiesWithoutPhoto": [
    { "id": "2026-08-14-national-002", "section": "national" }
  ],
  "validatorWarnings": [
    "2026-08-14-national-001 and 2026-08-14-local-001 cite the same source — same story published twice?"
  ],
  "validatorErrors": [
    "more than half the batch is missing photos — the photo step failed"
  ],
  "workarounds": [
    "El Progreso's site was unreachable; used La Voz de Galicia as the primary source for local-003 instead"
  ],
  "needsHumanAttention": true,
  "humanAttentionReason": "fetch-photos.mjs could not reach any source host — looks like an outbound network problem, not a content issue",
  "notes": ""
}
```

## Field reference

| Field | Type | Rules |
|---|---|---|
| `date` | string | `YYYY-MM-DD`, matches the filename. |
| `published` | bool | Whether `docs/latest.json` was updated this run. |
| `publishedAt` | ISO-8601 string or `null` | When it published, if it did. |
| `sections.present` / `sections.missing` | array of category strings | Every entry in `config.json → sections.order` goes in exactly one of the two lists. |
| `storiesWithoutPhoto` | array of `{id, section}` | Every article that shipped with no `imageURL`, or would have if this had published. Empty array, not omitted, when there are none. |
| `validatorWarnings` | array of strings | `validate.mjs`'s warnings verbatim, or as close to verbatim as practical. Empty array when there are none. |
| `validatorErrors` | array of strings | Populated when `published` is `false` — why `validate.mjs` failed. Empty array when it passed. |
| `workarounds` | array of strings | Anything that looked wrong that you routed around to get the run done. Empty array when there weren't any. |
| `needsHumanAttention` | bool | See below. |
| `humanAttentionReason` | string or `null` | Required (non-null) when `needsHumanAttention` is `true`. `null` otherwise. |
| `notes` | string | Anything else worth saying that doesn't fit the fields above. `""` when there's nothing to add. |

## `needsHumanAttention`

This is the one field the whole point of this file hangs on, so it's worth
being deliberate about. Set it `true` for things that are **outside Hermes's
own ability to fix by writing better content or better config** — the
research/writing/publishing process itself broke:

- A search or fetch tool erroring, timing out, or refusing to run at all
- Hitting a hard budget or credit limit rather than a soft one
- A source, script, or host being unreachable in a way that looks like
  infrastructure rather than one dead link
- Anything that stopped the run before it could even attempt to write a story

Leave it `false` for the ordinary, expected texture of a real run — a quiet
section with only two stories, a missing photo because no source had one, a
duplicate warning worth a second look, one dead link swapped for a working
one. **Those are Hermes doing its job**, not a reason to page anyone. The
`false` case is the common one; don't set `true` out of caution when a `false`
run with a clear report would do.

When in doubt: could rereading this report tomorrow, with no other
information, tell a human what to go check? If the answer is "the config or
the sources," that's `false` and belongs in `workarounds`/`notes`. If the
answer is "whatever ran this," that's `true`.
