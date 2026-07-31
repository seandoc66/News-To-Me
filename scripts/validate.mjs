#!/usr/bin/env node
// Validates a generated news feed against the contract in ../schema.md.
//
//   node scripts/validate.mjs [path/to/feed.json]
//
// Defaults to public/latest.json. Exits 0 if valid, 1 if not, printing every
// problem it found (not just the first). Run this BEFORE overwriting
// public/latest.json — if it fails, leave the previous day's file in place.

import { readFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const CATEGORIES = ["local", "national", "global", "tech", "ai"];
const SECTION_ORDER = new Map(CATEGORIES.map((c, i) => [c, i]));

const SUBTITLE_WORDS = { min: 20, max: 50 };
const BODY_WORDS = { min: 100, max: 300 };
const SOURCES = { min: 3, max: 4 };

const scriptDir = dirname(fileURLToPath(import.meta.url));
const feedRoot = resolve(scriptDir, "..");
const feedPath = process.argv[2]
  ? resolve(process.argv[2])
  : join(feedRoot, "docs", "latest.json");

const problems = [];
const warnings = [];
const fail = (msg) => problems.push(msg);
const warn = (msg) => warnings.push(msg);

const countWords = (s) => s.trim().split(/\s+/).filter(Boolean).length;

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
    if (!/^\d{4}-\d{2}-\d{2}-(local|national|global|tech|ai)-\d{3}$/.test(a.id)) {
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

  // body
  if (typeof a.body !== "string" || !a.body.trim()) {
    fail(`${at("body")} must be a non-empty string`);
  } else {
    const n = countWords(a.body);
    if (n < BODY_WORDS.min || n > BODY_WORDS.max) {
      fail(`${at("body")} is ${n} words — must be ${BODY_WORDS.min}–${BODY_WORDS.max}`);
    }
    if (/^#{1,6}\s|\*\*|\[.+\]\(.+\)/m.test(a.body)) {
      warn(`${at("body")} looks like it contains markdown — body should be plain prose`);
    }
  }

  // imageURL — self-hosted, so verify the file actually exists
  if (typeof a.imageURL !== "string" || !a.imageURL.trim()) {
    fail(`${at("imageURL")} must be a non-empty string`);
  } else if (a.imageURL.startsWith("/")) {
    const onDisk = join(feedRoot, "docs", a.imageURL.replace(/^\//, ""));
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

// Section ordering: articles should already be grouped local→national→global→tech→ai
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
  } else if (perCategory[c] > 10) {
    warn(`${perCategory[c]} "${c}" articles — more than expected (4–8 is typical)`);
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
