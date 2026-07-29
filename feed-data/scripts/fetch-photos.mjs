#!/usr/bin/env node
// Downloads each article's candidate photo, resizes it, and writes it to
// public/images/<article-id>.jpg.
//
//   node scripts/fetch-photos.mjs draft.json
//
// `draft.json` is a feed-shaped file where each article carries an extra
// `photoCandidate: { url, description, license }`. This script:
//
//   1. downloads the candidate (following redirects, with a real User-Agent —
//      Wikimedia rejects requests without one)
//   2. verifies the response is genuinely an image, not an HTML error page
//   3. resizes to max 1000px on the long edge, JPEG quality 75, via `sips`
//   4. writes public/images/<id>.jpg and rewrites `imageURL` to /images/<id>.jpg
//
// It prints a per-article result and rewrites the draft in place. Articles whose
// photo could not be fetched keep their `photoCandidate` so you can see what
// failed; `validate.mjs` will then fail on the missing image, which is the
// intended behaviour — a story with no photo shouldn't ship silently.

import { readFileSync, writeFileSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const MAX_EDGE = 1000;
const JPEG_QUALITY = 75;
const TIMEOUT_MS = 20_000;

const USER_AGENT =
  "PersonalNewsFeed/1.0 (single-user personal news app; contact: repo owner)";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const feedRoot = resolve(scriptDir, "..");
const imagesDir = join(feedRoot, "public", "images");

const draftPath = process.argv[2];
if (!draftPath) {
  console.error("usage: node scripts/fetch-photos.mjs <draft.json>");
  process.exit(1);
}
const resolvedDraft = resolve(draftPath);
if (!existsSync(resolvedDraft)) {
  console.error(`✗ not found: ${resolvedDraft}`);
  process.exit(1);
}

mkdirSync(imagesDir, { recursive: true });

const feed = JSON.parse(readFileSync(resolvedDraft, "utf8"));
if (!Array.isArray(feed.articles)) {
  console.error("✗ draft has no `articles` array");
  process.exit(1);
}

let ok = 0;
const failures = [];

for (const article of feed.articles) {
  const candidate = article.photoCandidate;
  const label = article.id ?? "(no id)";

  if (!candidate?.url) {
    failures.push(`${label}: no photoCandidate`);
    console.log(`  –  ${label}  no candidate`);
    continue;
  }

  const target = join(imagesDir, `${article.id}.jpg`);
  let temp;

  try {
    const response = await fetch(candidate.url, {
      redirect: "follow",
      headers: { "User-Agent": USER_AGENT, Accept: "image/*" },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.startsWith("image/")) {
      // Almost always means the URL was an HTML page, not the image itself.
      throw new Error(`not an image (content-type: ${contentType || "none"})`);
    }

    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length < 1024) {
      throw new Error(`suspiciously small (${bytes.length} bytes)`);
    }

    temp = join(tmpdir(), `photo-${article.id}-${bytes.length}`);
    writeFileSync(temp, bytes);

    // sips is built into macOS, so this needs no dependencies. -Z scales the
    // long edge while preserving aspect ratio.
    execFileSync(
      "sips",
      [
        "-s", "format", "jpeg",
        "-s", "formatOptions", String(JPEG_QUALITY),
        "-Z", String(MAX_EDGE),
        temp,
        "--out", target,
      ],
      { stdio: "pipe" }
    );

    const size = readFileSync(target).length;
    article.imageURL = `/images/${article.id}.jpg`;
    delete article.photoCandidate;
    ok += 1;
    console.log(
      `  ✓  ${label}  ${(size / 1024).toFixed(0)}KB  ${candidate.license ?? "license unstated"}`
    );
  } catch (err) {
    failures.push(`${label}: ${err.message}`);
    console.log(`  ✗  ${label}  ${err.message}`);
  } finally {
    if (temp && existsSync(temp)) rmSync(temp, { force: true });
  }
}

writeFileSync(resolvedDraft, JSON.stringify(feed, null, 2) + "\n");

console.log(`\n${ok}/${feed.articles.length} photos fetched → public/images/`);
if (failures.length) {
  console.log(`\n${failures.length} still need a photo:`);
  for (const f of failures) console.log(`  • ${f}`);
  console.log(
    `\nFind replacement images for these and re-run, or drop the stories.\n` +
    `validate.mjs will refuse to publish while an imageURL has no file behind it.`
  );
  process.exit(1);
}
