// Loads hermes/config.json — the single source of truth for every tunable
// setting. Imported by validate.mjs, fetch-photos.mjs and prune-images.mjs so
// the numbers can't drift apart, and so editing the config actually changes
// behaviour rather than only changing the prose that describes it.

import { readFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
export const repoRoot = resolve(scriptDir, "..");

const configPath = join(repoRoot, "hermes", "config.json");

if (!existsSync(configPath)) {
  console.error(`✗ Missing config: ${configPath}`);
  process.exit(1);
}

let parsed;
try {
  parsed = JSON.parse(readFileSync(configPath, "utf8"));
} catch (err) {
  console.error(`✗ hermes/config.json is not valid JSON: ${err.message}`);
  process.exit(1);
}

/// Fetches a nested value, failing loudly rather than silently falling back to a
/// default. A typo in the config should stop the run, not quietly restore the
/// old behaviour and leave someone wondering why their edit did nothing.
function required(path) {
  let node = parsed;
  for (const key of path.split(".")) {
    if (node === undefined || node === null || !(key in node)) {
      console.error(`✗ hermes/config.json is missing "${path}"`);
      process.exit(1);
    }
    node = node[key];
  }
  return node;
}

export const config = {
  raw: parsed,

  categories: required("sections.order"),
  storiesPerSection: required("sections.storiesPerSection"),

  subtitleWords: required("writing.subtitleWords"),
  bodyWords: required("writing.bodyWords"),
  sourcesPerArticle: required("writing.sourcesPerArticle"),

  photos: {
    maxLongEdge: required("photos.maxLongEdge"),
    jpegQuality: required("photos.jpegQuality"),
    minSourceLongEdge: required("photos.minSourceLongEdge"),
    minSourceShortEdge: required("photos.minSourceShortEdge"),
    retentionDays: required("photos.retentionDays"),
  },

  paths: {
    feed: required("publishing.feedPath"),
    archiveDir: required("publishing.archiveDir"),
    imagesDir: required("publishing.imagesDir"),
  },
};
