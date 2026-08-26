#!/usr/bin/env node
// Assembles a day's per-section drafts into one edition.
//
//   node scripts/merge-sections.mjs YYYY-MM-DD
//
// Reads drafts/<date>/<section>.json for every section in sections.order and
// writes docs/archive/<date>.json — the file fetch-photos.mjs and validate.mjs
// already expect. Nothing downstream changes.
//
// Why the split: the edition is 45-67KB of JSON, and writing it in one go put
// the whole run inside a single model response — see "Why section by section"
// in hermes/brief.md. Six files of ~8KB each cost one section when a write is
// truncated or the run's tool-call budget runs out, not the edition — and a
// re-run only has to redo the section that failed.
//
// Each part file is:
//
//   { "sources": [ { "name": "El Progreso", "url": "https://..." } ],
//     "articles": [ { ...schema.md article... } ] }
//
// `sources` are the outlets that section actually drew on today; the app shows
// them read-only under the Sections button. Article order within the file is
// the running order the app presents — most significant first.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { config, repoRoot } from "./config.mjs";

const CATEGORIES = config.categories;
// config.storiesPerSection is keyed by category (see scripts/config.mjs) —
// each section can have its own min/max, not one range for all six.
const rangeFor = (category) => config.storiesPerSection[category];

const date = process.argv[2];
if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
  console.error("✗ Usage: node scripts/merge-sections.mjs YYYY-MM-DD");
  process.exit(1);
}

const partsDir = join(repoRoot, "drafts", date);
const outPath = join(repoRoot, config.paths.archiveDir, `${date}.json`);

const problems = [];
const warnings = [];
const fail = (msg) => problems.push(msg);
const warn = (msg) => warnings.push(msg);

// --- read the parts ---------------------------------------------------------

const ID_PATTERN = new RegExp(`^${date}-(${CATEGORIES.join("|")})-\\d{3}$`);

const articles = [];
const sections = {};
const seenIds = new Set();
let partsFound = 0;

for (const category of CATEGORIES) {
  const partPath = join(partsDir, `${category}.json`);

  // A section with no part file is thin-but-legitimate — the brief treats an
  // empty section as a correct outcome on a quiet day, so this warns rather
  // than fails. It is still worth saying out loud: the same silence is what a
  // truncated write leaves behind, and those two need telling apart.
  if (!existsSync(partPath)) {
    warn(`no draft for "${category}" (${partPath}) — section will be empty`);
    sections[category] = { ...rangeFor(category), sources: [] };
    continue;
  }

  partsFound += 1;

  let part;
  try {
    part = JSON.parse(readFileSync(partPath, "utf8"));
  } catch (err) {
    fail(`${category}.json is not valid JSON: ${err.message}`);
    continue;
  }

  if (!Array.isArray(part?.articles)) {
    fail(`${category}.json has no "articles" array`);
    continue;
  }
  if (part.sources !== undefined && !Array.isArray(part.sources)) {
    fail(`${category}.json has a "sources" that isn't an array`);
    continue;
  }

  sections[category] = { ...rangeFor(category), sources: part.sources ?? [] };

  part.articles.forEach((article, i) => {
    const where = `${category}.json article ${i + 1}`;

    if (typeof article?.id !== "string" || !ID_PATTERN.test(article.id)) {
      fail(`${where}: id ${JSON.stringify(article?.id)} isn't ${date}-${category}-NNN`);
    } else if (seenIds.has(article.id)) {
      // The app dedupes and tracks saved state by id, so a collision silently
      // drops a story on the phone rather than failing anywhere visible.
      fail(`${where}: duplicate id ${article.id}`);
    } else {
      seenIds.add(article.id);
      if (!article.id.startsWith(`${date}-${category}-`)) {
        fail(`${where}: id ${article.id} doesn't belong to this section`);
      }
    }

    if (article?.category !== category) {
      fail(`${where}: category ${JSON.stringify(article?.category)} doesn't match the file it's in`);
    }

    articles.push(article);
  });
}

// Every section missing means the writing step never ran, not that the news was
// quiet. Publishing an empty edition over a good one is the worse failure.
if (partsFound === 0) {
  fail(`no section drafts at all in ${partsDir}`);
}

// --- report and write -------------------------------------------------------

if (warnings.length) {
  console.log(`${warnings.length} warning${warnings.length === 1 ? "" : "s"}:`);
  for (const w of warnings) console.log(`  ⚠ ${w}`);
  console.log("");
}

if (problems.length) {
  console.error(`${problems.length} error${problems.length === 1 ? "" : "s"}:`);
  for (const p of problems) console.error(`  ✗ ${p}`);
  console.error(`\nMERGE FAILED — docs/archive/${date}.json not written.`);
  process.exit(1);
}

// generatedAt and the min/max targets are mirrored from hermes/config.json
// rather than written by hand, so they can't drift from what the config says.
const edition = {
  generatedAt: new Date().toISOString(),
  config: { sections },
  articles,
};

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, `${JSON.stringify(edition, null, 2)}\n`);

const counts = CATEGORIES.map((c) => `${c} ${articles.filter((a) => a.category === c).length}`).join(", ");
console.log(`Wrote ${outPath}`);
console.log(`${articles.length} articles — ${counts}`);
console.log(`\n✓ Merged — run fetch-photos.mjs next.`);
process.exit(0);
