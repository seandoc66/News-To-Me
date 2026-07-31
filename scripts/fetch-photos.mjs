#!/usr/bin/env node
// Downloads each article's candidate photo, resizes it, and writes it to
// docs/images/<article-id>.jpg.
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
//   4. writes docs/images/<id>.jpg and rewrites `imageURL` to /images/<id>.jpg
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

// Wikimedia rate-limits unauthenticated bursts and starts returning 429 after a
// couple of rapid requests, so downloads are spaced out and retried with
// backoff. Without this, a full day's batch fails almost entirely.
const DELAY_MS = 1_500;
const MAX_ATTEMPTS = 4;
const BACKOFF_MS = 5_000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const USER_AGENT =
  "PersonalNewsFeed/1.0 (single-user personal news app; contact: repo owner)";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const feedRoot = resolve(scriptDir, "..");
const imagesDir = join(feedRoot, "docs", "images");

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

/// Fetches with backoff on 429/5xx, which Wikimedia returns readily.
async function fetchWithRetry(url) {
  let lastError;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(url, {
        redirect: "follow",
        headers: { "User-Agent": USER_AGENT, Accept: "image/*" },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (response.status === 429 || response.status >= 500) {
        lastError = new Error(`HTTP ${response.status}`);
        if (attempt < MAX_ATTEMPTS) {
          const wait = BACKOFF_MS * attempt;
          console.log(`     …${response.status}, retrying in ${wait / 1000}s`);
          await sleep(wait);
          continue;
        }
      }
      return response;
    } catch (err) {
      lastError = err;
      if (attempt < MAX_ATTEMPTS) await sleep(BACKOFF_MS * attempt);
    }
  }
  throw lastError ?? new Error("fetch failed");
}

let ok = 0;
let attempted = 0;
const failures = [];

for (const article of feed.articles) {
  const candidate = article.photoCandidate;
  const label = article.id ?? "(no id)";

  // Already has a photo from an earlier run — skip, so re-running after a
  // partial failure only retries what's still missing.
  if (!candidate?.url && article.imageURL) {
    ok += 1;
    continue;
  }

  if (!candidate?.url) {
    failures.push(`${label}: no photoCandidate`);
    console.log(`  –  ${label}  no candidate`);
    continue;
  }

  if (attempted > 0) await sleep(DELAY_MS);
  attempted += 1;

  const target = join(imagesDir, `${article.id}.jpg`);
  let temp;

  try {
    const response = await fetchWithRetry(candidate.url);

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

console.log(`\n${ok}/${feed.articles.length} photos fetched → docs/images/`);
if (failures.length) {
  console.log(`\n${failures.length} still need a photo:`);
  for (const f of failures) console.log(`  • ${f}`);
  console.log(
    `\nFind replacement images for these and re-run, or drop the stories.\n` +
    `validate.mjs will refuse to publish while an imageURL has no file behind it.`
  );
  process.exit(1);
}
