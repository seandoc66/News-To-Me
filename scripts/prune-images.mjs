#!/usr/bin/env node
// Deletes photos older than the retention window so the git repo doesn't grow
// without bound.
//
//   node scripts/prune-images.mjs            # delete anything older than 14 days
//   node scripts/prune-images.mjs --dry-run  # list what would go
//   node scripts/prune-images.mjs --days 30
//
// Age comes from the date prefix in the filename (article ids start
// YYYY-MM-DD-), not the filesystem mtime — a fresh `git clone` rewrites every
// mtime to checkout time, which would make mtime-based pruning silently do
// nothing.
//
// Photos still referenced by public/latest.json are always kept, whatever their
// age, so the live feed can never end up pointing at a deleted file.

import { readdirSync, existsSync, readFileSync, rmSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DEFAULT_DAYS = 14;

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const daysArg = args.indexOf("--days");
const days = daysArg !== -1 ? Number(args[daysArg + 1]) : DEFAULT_DAYS;

if (!Number.isFinite(days) || days < 1) {
  console.error("✗ --days must be a positive number");
  process.exit(1);
}

const scriptDir = dirname(fileURLToPath(import.meta.url));
const feedRoot = resolve(scriptDir, "..");
const imagesDir = join(feedRoot, "docs", "images");
const latestPath = join(feedRoot, "docs", "latest.json");

if (!existsSync(imagesDir)) {
  console.log("No images directory — nothing to prune.");
  process.exit(0);
}

// Anything the live feed still points at is off limits.
const referenced = new Set();
if (existsSync(latestPath)) {
  try {
    const feed = JSON.parse(readFileSync(latestPath, "utf8"));
    for (const article of feed.articles ?? []) {
      if (typeof article.imageURL === "string") {
        referenced.add(article.imageURL.replace(/^\/images\//, ""));
      }
    }
  } catch (err) {
    // Better to prune nothing than to delete a photo the live feed needs.
    console.error(`✗ could not read latest.json (${err.message}) — aborting to be safe`);
    process.exit(1);
  }
}

const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
const cutoffDay = cutoff.toISOString().slice(0, 10);

const files = readdirSync(imagesDir).filter((f) => !f.startsWith("."));
const doomed = [];
let keptReferenced = 0;
let keptRecent = 0;
let undated = 0;

for (const file of files) {
  const match = file.match(/^(\d{4}-\d{2}-\d{2})-/);
  if (!match) {
    undated += 1;
    continue;
  }
  if (referenced.has(file)) {
    keptReferenced += 1;
    continue;
  }
  if (match[1] >= cutoffDay) {
    keptRecent += 1;
    continue;
  }
  doomed.push(file);
}

let freed = 0;
for (const file of doomed) {
  const path = join(imagesDir, file);
  freed += statSync(path).size;
  if (!dryRun) rmSync(path, { force: true });
}

const mb = (freed / 1024 / 1024).toFixed(1);
console.log(
  dryRun
    ? `Would delete ${doomed.length} photo(s), freeing ${mb}MB (older than ${cutoffDay})`
    : `Deleted ${doomed.length} photo(s), freed ${mb}MB (older than ${cutoffDay})`
);
console.log(`Kept: ${keptRecent} recent, ${keptReferenced} referenced by latest.json`);
if (undated) {
  console.log(`Ignored ${undated} file(s) with no YYYY-MM-DD- prefix`);
}
