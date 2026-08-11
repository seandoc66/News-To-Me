#!/usr/bin/env node
// Validates a generated news feed against the contract in ../schema.md.
//
//   node scripts/validate.mjs [path/to/feed.json]
//
// Defaults to docs/latest.json. Exits 0 if valid, 1 if not, printing every
// problem it found (not just the first). Run this BEFORE overwriting
// docs/latest.json — if it fails, leave the previous day's file in place.

import { readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { config, repoRoot } from "./config.mjs";

// Every limit below comes from hermes/config.json — see scripts/config.mjs.
const CATEGORIES = config.categories;
const SECTION_ORDER = new Map(CATEGORIES.map((c, i) => [c, i]));

const SUBTITLE_WORDS = config.subtitleWords;
const BODY_WORDS = config.bodyWords;
const PARAGRAPH_WORDS = config.paragraphWords;
const SUBHEADS_ABOVE_WORDS = config.subheadsAboveWords;
const SOURCES = config.sourcesPerArticle;
const MAX_PER_SECTION = config.storiesPerSection.max;

// Built from the configured categories so adding a section needs no code change.
const ID_PATTERN = new RegExp(`^\\d{4}-\\d{2}-\\d{2}-(${CATEGORIES.join("|")})-\\d{3}$`);

const feedRoot = repoRoot;
const feedPath = process.argv[2]
  ? resolve(process.argv[2])
  : join(feedRoot, config.paths.feed);

const problems = [];
const warnings = [];
const fail = (msg) => problems.push(msg);
const warn = (msg) => warnings.push(msg);

const countWords = (s) => s.trim().split(/\s+/).filter(Boolean).length;

// --- body markdown ----------------------------------------------------------

/// Splits a body into the blocks the app renders.
///
/// `body` is Markdown, but only a deliberately small subset of it: paragraphs
/// separated by a blank line, `## ` subheads, and inline emphasis. This walks it
/// line by line rather than splitting on blank lines, because that is what
/// `StoryBlock.parse` in the app does — a subhead is its own block whether or not
/// a blank line happens to precede it, so the validator sees what the phone sees.
const parseBlocks = (body) => {
  const blocks = [];
  let paragraph = [];
  const flush = () => {
    if (paragraph.length) {
      blocks.push({ kind: "paragraph", text: paragraph.join(" ") });
      paragraph = [];
    }
  };

  for (const raw of body.replace(/\r\n/g, "\n").split("\n")) {
    const line = raw.trim();
    const heading = line.match(/^(#{1,6})\s+(.*)$/);
    if (!line) {
      flush();
    } else if (heading) {
      flush();
      blocks.push({ kind: "subhead", level: heading[1].length, text: heading[2].trim() });
    } else {
      paragraph.push(line);
    }
  }
  flush();
  return blocks;
};

/// Inline syntax removed, so word counts measure prose rather than punctuation.
const stripInline = (s) =>
  s
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/(\*\*|__|\*|_|`)/g, "");

/// Markdown the app doesn't render. None of it is fatal — the renderer degrades
/// to showing the literal characters — but all of it means the generator reached
/// for syntax the contract doesn't offer, which is worth seeing.
const OUTSIDE_SUBSET = [
  [/^\s*([-*+]|\d+[.)])\s+\S/m, "a list"],
  [/^\s*>/m, "a blockquote"],
  [/^\s*(```|~~~)/m, "a code fence"],
  [/!\[[^\]]*\]\([^)]*\)/, "an image"],
  [/(^|[^!])\[[^\]]+\]\([^)]+\)/, "a link — sources belong in `sources`, not the body"],
  [/^\s*\|.*\|\s*$/m, "a table"],
];

/// True when a URL points at an individual story rather than a masthead or
/// section index.
///
/// Depth alone isn't enough: plenty of sites publish stories at the root with a
/// slug ("/denuncian-agresion-a-un-menor-en-sarria"), which is one segment deep
/// yet obviously a story, while "/news" is one segment and obviously not. So a
/// lone segment counts when it looks like a slug — hyphenated or long — or when
/// a query string identifies the item.
const isStoryURL = (raw) => {
  try {
    const u = new URL(raw);
    const segments = u.pathname.split("/").filter(Boolean);
    if (segments.length >= 2) return true;
    if (segments.length === 0) return false;
    const slug = segments[0];
    return u.search.length > 1 || slug.includes("-") || slug.length > 15;
  } catch {
    return false;
  }
};

const isISODate = (s) =>
  typeof s === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(s) &&
  !Number.isNaN(Date.parse(s));

// --- load -------------------------------------------------------------------

if (!existsSync(feedPath)) {
  console.error(`✗ Feed file not found: ${feedPath}`);
  process.exit(1);
}

let feed;
try {
  feed = JSON.parse(readFileSync(feedPath, "utf8"));
} catch (err) {
  console.error(`✗ ${feedPath} is not valid JSON: ${err.message}`);
  process.exit(1);
}

// --- top level --------------------------------------------------------------

if (!isISODate(feed.generatedAt)) {
  fail(`generatedAt must be an ISO-8601 timestamp, got: ${JSON.stringify(feed.generatedAt)}`);
}

if (!Array.isArray(feed.articles)) {
  console.error("✗ `articles` must be an array");
  process.exit(1);
}
if (feed.articles.length === 0) {
  fail("`articles` is empty — nothing to show");
}

// --- per article ------------------------------------------------------------

const seenIds = new Set();
const seenHeadlines = new Map();
const seenSourceUrls = new Map();
const missingPhotos = [];
const reportedPairs = new Set();
const perCategory = Object.fromEntries(CATEGORIES.map((c) => [c, 0]));

feed.articles.forEach((a, i) => {
  const at = (field) => `articles[${i}]${field ? "." + field : ""}${a?.id ? ` (${a.id})` : ""}`;

  if (typeof a !== "object" || a === null) {
    fail(`${at()} is not an object`);
    return;
  }

  // id
  if (typeof a.id !== "string" || !a.id.trim()) {
    fail(`${at("id")} must be a non-empty string`);
  } else {
    if (!ID_PATTERN.test(a.id)) {
      warn(`${at("id")} doesn't match the YYYY-MM-DD-category-NNN convention: "${a.id}"`);
    }
    if (seenIds.has(a.id)) fail(`${at("id")} duplicate id: "${a.id}"`);
    seenIds.add(a.id);
  }

  // category
  if (!CATEGORIES.includes(a.category)) {
    fail(`${at("category")} must be one of ${CATEGORIES.join(", ")}, got: ${JSON.stringify(a.category)}`);
  } else {
    perCategory[a.category] += 1;
    // id should agree with category
    if (typeof a.id === "string" && !a.id.includes(`-${a.category}-`)) {
      warn(`${at()} category "${a.category}" doesn't match its id`);
    }
  }

  // headline
  if (typeof a.headline !== "string" || !a.headline.trim()) {
    fail(`${at("headline")} must be a non-empty string`);
  } else {
    if (a.headline.trim().endsWith(".")) {
      warn(`${at("headline")} ends with a period — headline style omits it`);
    }
    if (a.headline.length > 120) {
      warn(`${at("headline")} is ${a.headline.length} chars — may wrap awkwardly on a phone`);
    }
    const key = a.headline.trim().toLowerCase();
    if (seenHeadlines.has(key)) {
      fail(`${at("headline")} duplicates the headline of ${seenHeadlines.get(key)}`);
    } else {
      seenHeadlines.set(key, at());
    }
  }

  // subtitle
  if (typeof a.subtitle !== "string" || !a.subtitle.trim()) {
    fail(`${at("subtitle")} must be a non-empty string`);
  } else {
    const n = countWords(a.subtitle);
    if (n < SUBTITLE_WORDS.min || n > SUBTITLE_WORDS.max) {
      fail(`${at("subtitle")} is ${n} words — must be ${SUBTITLE_WORDS.min}–${SUBTITLE_WORDS.max}`);
    }
  }

  // body — Markdown, restricted to paragraphs, `## ` subheads and inline emphasis.
  if (typeof a.body !== "string" || !a.body.trim()) {
    fail(`${at("body")} must be a non-empty string`);
  } else {
    const blocks = parseBlocks(a.body);
    const paragraphs = blocks.filter((b) => b.kind === "paragraph");
    const subheads = blocks.filter((b) => b.kind === "subhead");

    if (!paragraphs.length) {
      fail(`${at("body")} has no prose — only subheads`);
    }

    // Subhead text is navigation, not story. Counting it would quietly shrink
    // every structured article against a range that has always meant prose.
    const n = paragraphs.reduce((sum, p) => sum + countWords(stripInline(p.text)), 0);
    if (n < BODY_WORDS.min || n > BODY_WORDS.max) {
      fail(
        `${at("body")} is ${n} words of prose — must be ${BODY_WORDS.min}–${BODY_WORDS.max}` +
        (subheads.length ? ` (subheads excluded)` : "")
      );
    }

    for (const [pattern, what] of OUTSIDE_SUBSET) {
      if (pattern.test(a.body)) {
        warn(`${at("body")} contains ${what} — the body subset is paragraphs, "## " subheads and inline emphasis`);
      }
    }

    paragraphs.forEach((p, k) => {
      const words = countWords(stripInline(p.text));
      if (words > PARAGRAPH_WORDS.max) {
        warn(
          `${at("body")} paragraph ${k + 1} is ${words} words — over ${PARAGRAPH_WORDS.max}, ` +
          `which reads as a wall of text on a phone. Aim for ${PARAGRAPH_WORDS.min}–${PARAGRAPH_WORDS.max}`
        );
      }
    });

    if (subheads.length) {
      if (n < SUBHEADS_ABOVE_WORDS) {
        warn(
          `${at("body")} has ${subheads.length} subhead(s) in a ${n}-word story — ` +
          `below ${SUBHEADS_ABOVE_WORDS} words they divide a story too short to need dividing`
        );
      }
      if (blocks[0].kind === "subhead") {
        warn(`${at("body")} opens with a subhead — the story should start on prose, under its own headline`);
      }
      if (blocks[blocks.length - 1].kind === "subhead") {
        warn(`${at("body")} ends with a subhead — it has no text under it`);
      }
      for (const s of subheads) {
        if (s.level === 1) {
          warn(`${at("body")} uses "# ${s.text}" — the headline owns that level; subheads are "## "`);
        }
        if (!s.text) {
          warn(`${at("body")} has an empty subhead`);
        } else if (s.text.endsWith(".")) {
          warn(`${at("body")} subhead "${s.text}" ends with a period — subheads are headline style`);
        } else if (s.text.length > 60) {
          warn(`${at("body")} subhead "${s.text}" is ${s.text.length} chars — subheads should be a few words`);
        }
      }
    }
  }

  // imageURL — optional. A story with no photo still publishes and renders with
  // the category-tinted fallback; blocking a whole edition over one missing
  // image costs far more than one plainer card. When a path IS given it must be
  // well-formed and the file must exist, since a broken path is a bug rather
  // than an accepted absence.
  if (a.imageURL === undefined || a.imageURL === null || a.imageURL === "") {
    missingPhotos.push(a.id ?? at());
  } else if (typeof a.imageURL !== "string" || !a.imageURL.trim()) {
    fail(`${at("imageURL")} must be a string path, an absolute URL, or omitted entirely`);
  } else if (a.imageURL.startsWith("/")) {
    const onDisk = join(feedRoot, config.paths.imagesDir, "..", a.imageURL.replace(/^\//, ""));
    if (!existsSync(onDisk)) {
      fail(`${at("imageURL")} points at a file that doesn't exist: docs${a.imageURL}`);
    }
  } else if (/^https?:\/\//.test(a.imageURL)) {
    warn(`${at("imageURL")} is an absolute URL — fine for Blob storage, but self-hosted photos should use /images/<id>.jpg`);
  } else {
    fail(`${at("imageURL")} must be either "/images/..." or an absolute http(s) URL, got: "${a.imageURL}"`);
  }

  // sources
  if (!Array.isArray(a.sources)) {
    fail(`${at("sources")} must be an array`);
  } else {
    if (a.sources.length < SOURCES.min || a.sources.length > SOURCES.max) {
      fail(`${at("sources")} has ${a.sources.length} entries — must be ${SOURCES.min}–${SOURCES.max}`);
    }
    const seenUrls = new Set();
    a.sources.forEach((s, j) => {
      const sat = `${at("sources")}[${j}]`;
      if (typeof s !== "object" || s === null) {
        fail(`${sat} is not an object`);
        return;
      }
      if (typeof s.name !== "string" || !s.name.trim()) {
        fail(`${sat}.name must be a non-empty string`);
      }
      if (typeof s.url !== "string" || !/^https?:\/\/\S+$/.test(s.url)) {
        fail(`${sat}.url must be an http(s) URL, got: ${JSON.stringify(s.url)}`);
      } else {
        if (seenUrls.has(s.url)) fail(`${sat}.url is a duplicate within this article`);
        seenUrls.add(s.url);
        // Two articles citing the same *story* URL are almost always the same
        // story written twice — usually across sections, since tech and ai
        // overlap. Reworded headlines slip past the exact-match headline check,
        // so this is what actually catches a duplicate.
        //
        // Only deep links count. A masthead like bbc.com/news gets cited by
        // several unrelated stories quite legitimately, and treating that as a
        // duplicate would be a false positive on most batches.
        if (isStoryURL(s.url)) {
          const owner = seenSourceUrls.get(s.url);
          if (owner) {
            // Report once per pair, not once per shared link — a genuine
            // duplicate usually shares every source it has.
            const pair = [owner, a.id].sort().join(" | ");
            if (!reportedPairs.has(pair)) {
              reportedPairs.add(pair);
              warn(
                `${a.id} and ${owner} cite the same source (${s.url}) — ` +
                `check these aren't the same story published twice`
              );
            }
          } else if (a.id) {
            seenSourceUrls.set(s.url, a.id);
          }
        } else {
          fail(
            `${sat}.url is a section or home page (${s.url}), not the story itself — ` +
            `it's a dead end when tapped`
          );
        }
        try {
          new URL(s.url);
        } catch {
          fail(`${sat}.url is not parseable: "${s.url}"`);
        }
      }
    });
  }

  // publishedAt
  if (!isISODate(a.publishedAt)) {
    fail(`${at("publishedAt")} must be an ISO-8601 timestamp, got: ${JSON.stringify(a.publishedAt)}`);
  }
});

// --- feed-level shape -------------------------------------------------------

// Section ordering: articles should already be grouped in sections.order
let lastRank = -1;
let orderBroken = false;
for (const a of feed.articles) {
  const rank = SECTION_ORDER.get(a.category);
  if (rank === undefined) continue;
  if (rank < lastRank) {
    orderBroken = true;
    break;
  }
  lastRank = rank;
}
if (orderBroken) {
  warn(`articles are not grouped in section order (${CATEGORIES.join(" → ")}) — the app sorts defensively, but emit them sorted`);
}

for (const c of CATEGORIES) {
  if (perCategory[c] === 0) {
    warn(`no "${c}" articles in this batch`);
  } else if (perCategory[c] > MAX_PER_SECTION * 1.5) {
    warn(`${perCategory[c]} "${c}" articles — well above the ${config.storiesPerSection.min}–${MAX_PER_SECTION} the config aims for`);
  }
}

// Photos are optional, but a batch that has largely given up on them is a
// broken pipeline rather than an unlucky day, so say so loudly.
if (missingPhotos.length) {
  const share = missingPhotos.length / feed.articles.length;
  const list = missingPhotos.join(", ");
  if (share > 0.5) {
    fail(
      `${missingPhotos.length} of ${feed.articles.length} articles have no photo — ` +
      `that's over half the batch, which suggests the photo step failed rather than ` +
      `a few images being unavailable: ${list}`
    );
  } else {
    warn(
      `${missingPhotos.length} article(s) publishing without a photo — ` +
      `these render with the category gradient: ${list}`
    );
  }
}

// --- config (optional) ------------------------------------------------------

// Descriptive only: the app shows this read-only. Absent is fine — but a
// malformed block would silently drop sections from the Sections screen, so
// check the shape when one is present.
if (feed.config !== undefined) {
  const cfg = feed.config;
  if (cfg === null || typeof cfg !== "object" || Array.isArray(cfg)) {
    fail(`config must be an object when present, got: ${JSON.stringify(cfg)}`);
  } else if (cfg.sections !== undefined) {
    const sections = cfg.sections;
    if (sections === null || typeof sections !== "object" || Array.isArray(sections)) {
      fail(`config.sections must be an object keyed by category`);
    } else {
      for (const [key, section] of Object.entries(sections)) {
        const at = (f) => `config.sections.${key}.${f}`;
        if (!CATEGORIES.includes(key)) {
          warn(`config.sections has an unknown category "${key}" — the app ignores it`);
          continue;
        }
        if (section === null || typeof section !== "object" || Array.isArray(section)) {
          fail(`config.sections.${key} must be an object`);
          continue;
        }
        for (const bound of ["min", "max"]) {
          const v = section[bound];
          if (v !== undefined && (!Number.isInteger(v) || v < 0)) {
            fail(`${at(bound)} must be a non-negative integer, got: ${JSON.stringify(v)}`);
          }
        }
        if (
          Number.isInteger(section.min) &&
          Number.isInteger(section.max) &&
          section.min > section.max
        ) {
          fail(`${at("min")} (${section.min}) is greater than ${at("max")} (${section.max})`);
        }
        if (section.sources !== undefined) {
          if (!Array.isArray(section.sources)) {
            fail(`${at("sources")} must be an array`);
          } else {
            section.sources.forEach((s, i) => {
              if (s === null || typeof s !== "object" || Array.isArray(s)) {
                fail(`${at(`sources[${i}]`)} must be an object`);
                return;
              }
              if (typeof s.name !== "string" || !s.name.trim()) {
                fail(`${at(`sources[${i}]`)}.name must be a non-empty string`);
              }
              // url is optional — some sources are named pages with no clean link.
              if (s.url !== undefined && !/^https?:\/\//.test(String(s.url))) {
                fail(`${at(`sources[${i}]`)}.url must be an http(s) URL when present, got: ${JSON.stringify(s.url)}`);
              }
            });
          }
        }
      }
      for (const c of CATEGORIES) {
        if (sections[c] === undefined) {
          warn(`config.sections has no "${c}" entry — that section won't appear on the Sections screen`);
        }
      }
    }
  }
}

// --- report -----------------------------------------------------------------

const counts = CATEGORIES.map((c) => `${c} ${perCategory[c]}`).join(", ");
console.log(`Feed: ${feedPath}`);
console.log(`${feed.articles.length} articles — ${counts}`);

if (warnings.length) {
  console.log(`\n${warnings.length} warning${warnings.length === 1 ? "" : "s"}:`);
  for (const w of warnings) console.log(`  ⚠ ${w}`);
}

if (problems.length) {
  console.error(`\n${problems.length} error${problems.length === 1 ? "" : "s"}:`);
  for (const p of problems) console.error(`  ✗ ${p}`);
  console.error(`\nVALIDATION FAILED — do not publish. Leave the previous latest.json in place.`);
  process.exit(1);
}

console.log(`\n✓ Valid — safe to publish.`);
process.exit(0);
