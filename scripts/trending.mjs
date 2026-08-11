#!/usr/bin/env node
// Reads which of Shane's own trusted outlets are covering the same story
// right now, as a coverage-corroboration signal Hermes can weigh before
// spending `web_search` budget deciding what's actually big. See
// ARCHITECTURE.md for why this exists.
//
// Pulls the last 24h of articles from the outlets already in
// hermes/config.json → sources for a section, via GDELT's free DOC 2.0 API,
// and flags which stories more than one of those outlets is covering. One
// outlet running a story is routine; three of Shane's six trusted NI outlets
// running the same story on the same day is real corroboration — and it
// costs zero `web_search` budget, since it runs before Hermes starts
// researching.
//
//   node scripts/trending.mjs              all sections, in config order
//   node scripts/trending.mjs global       one section only
//
// GDELT DOC 2.0 API: free, no key, but rate-limited more tightly than its own
// docs suggest — repeated quick testing has been observed to trip a
// connection-level block (not just a 429), so this deliberately paces
// requests well below what GDELT asks for and never lets a failure block the
// run. A day with no signal is a correct, silent outcome, the same way an
// empty section or a missing photo is elsewhere in this pipeline.
// https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/

import { config } from "./config.mjs";

const GDELT_URL = "https://api.gdeltproject.org/api/v2/doc/doc";
const USER_AGENT =
  "PersonalNewsFeed/1.0 (single-user personal news app; contact: repo owner)";
const TIMEOUT_MS = 20_000;
const DELAY_MS = 15_000; // GDELT asks for ~1 request per 5s; this leaves 3x headroom
const MAX_ATTEMPTS = 4;
const BACKOFF_BASE_MS = 10_000; // 10s, 20s, 40s — exponential, plus jitter

// GDELT needs registrable domains and an ISO language code, not the
// human-readable names and per-section prose in config.json → sources /
// locale.outputLanguage. There's no canonical-domain field in the config
// schema today, so this is a hand-maintained mirror of that list. Known gap:
// if `sources` changes, this needs updating by hand — see ARCHITECTURE.md.
//
// Local government press pages (lugo.gal, deputacionlugo.gal), Hacker News
// and arXiv are expected to come back thin or empty: GDELT indexes
// broadcast/wire/newspaper-style journalism, not forums, preprints or
// municipal press releases. An empty result from those is correct, not a
// bug — the outlets stay listed because a hit is still worth surfacing.
const SECTION_LANG = {
  local: "spa",
  national: "spa",
  northernIreland: "eng",
  global: "eng",
  tech: "eng",
  ai: "eng",
};

const SECTION_DOMAINS = {
  local: {
    "elprogreso.es": "El Progreso",
    "lavozdegalicia.es": "La Voz de Galicia",
    "elcorreogallego.es": "El Correo Gallego",
    "lugo.gal": "Concello de Lugo press page",
    "deputacionlugo.gal": "Deputación de Lugo press page",
  },
  national: {
    "elpais.com": "El País",
    "elmundo.es": "El Mundo",
    "rtve.es": "RTVE",
    "20minutos.es": "20minutos",
    "publico.es": "Público",
    "europapress.es": "Europa Press",
  },
  northernIreland: {
    "bbc.co.uk": "BBC News NI",
    "belfasttelegraph.co.uk": "Belfast Telegraph",
    "irishnews.com": "The Irish News",
    "newsletter.co.uk": "News Letter",
    "strabanechronicle.com": "Strabane Chronicle",
    "derryjournal.com": "Derry Journal",
  },
  global: {
    "bbc.com": "BBC",
    "reuters.com": "Reuters",
    "apnews.com": "AP",
    "theguardian.com": "The Guardian",
  },
  tech: {
    "news.ycombinator.com": "Hacker News",
    "techcrunch.com": "TechCrunch",
    "wired.com": "Wired",
    "venturebeat.com": "VentureBeat",
    "theverge.com": "The Verge",
    "arxiv.org": "arXiv",
  },
  ai: {
    // config.json's `ai` source list is "these three, plus the tech sources
    // above" — the tech domains aren't repeated here, since running `tech`
    // in the same invocation already fetches them once.
    "simonwillison.net": "Simon Willison's blog",
    "anthropic.com": "Anthropic blog",
    "openai.com": "OpenAI blog",
  },
};

const requested = process.argv[2];
if (requested && !SECTION_DOMAINS[requested]) {
  console.error(
    `usage: node scripts/trending.mjs [${Object.keys(SECTION_DOMAINS).join("|")}]\n` +
      `(no argument runs every section in config order)`
  );
  process.exit(1);
}

// config.categories is sections.order from config.json — stay in that order
// so output reads the same way the edition does, and skip any section that
// doesn't have a domain map yet rather than erroring.
const sectionsToRun = requested
  ? [requested]
  : config.categories.filter((s) => SECTION_DOMAINS[s]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const jitter = () => Math.floor(Math.random() * 2000);

/// Fetches one domain's recent articles, retrying on failure — GDELT's own
/// rate-limit (429), a 5xx, or a dropped connection — with growing backoff.
/// Never throws: a domain that never answers is reported and skipped, the
/// same way fetch-photos.mjs treats a photo that never downloads.
async function fetchDomain(domain, lang) {
  const params = new URLSearchParams({
    query: `domainis:${domain} sourcelang:${lang}`,
    mode: "artlist",
    format: "json",
    timespan: "1d",
    maxrecords: "75",
    sort: "datedesc",
  });
  let lastError;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(`${GDELT_URL}?${params}`, {
        headers: { "User-Agent": USER_AGENT },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (response.status === 429 || response.status >= 500) {
        lastError = new Error(`HTTP ${response.status}`);
        if (attempt < MAX_ATTEMPTS) {
          await sleep(BACKOFF_BASE_MS * 2 ** (attempt - 1) + jitter());
          continue;
        }
      }
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const text = await response.text();
      if (!text.trim()) return [];
      return JSON.parse(text).articles ?? [];
    } catch (err) {
      lastError = err;
      if (attempt < MAX_ATTEMPTS) {
        await sleep(BACKOFF_BASE_MS * 2 ** (attempt - 1) + jitter());
      }
    }
  }
  const cause = lastError?.cause?.code ?? lastError?.cause?.message;
  console.error(
    `  ✗ ${domain}: ${lastError?.message ?? "failed"}${cause ? ` (${cause})` : ""}`
  );
  return [];
}

/// Extracts consecutive Title-Case word runs (2-4 words) from a headline as
/// candidate entity phrases — "New Forest", "Trump Media", "Michael Sheen".
/// Single capitalised words are skipped entirely: a headline's first word is
/// always capitalised regardless of meaning, which makes lone words too noisy
/// a signal to cluster on. This is tuned for English capitalisation rules and
/// is a weak signal on the Spanish sections (`local`, `national`) — Spanish
/// doesn't title-case common nouns the way English does, so it will under-
/// cluster there. Known gap, not fixed in this prototype.
function extractPhrases(title) {
  const words = title.split(/\s+/).filter(Boolean);
  const phrases = [];
  let run = [];
  const flush = () => {
    if (run.length >= 2 && run.length <= 4) phrases.push(run.join(" "));
    run = [];
  };
  for (const word of words) {
    const clean = word.replace(/[^\p{L}\p{N}'-]/gu, "");
    if (/^[A-Z][\p{L}'-]*$/u.test(clean) && clean.length > 1) {
      run.push(clean);
    } else {
      flush();
    }
  }
  flush();
  return phrases;
}

async function runSection(section, isFirstOverall) {
  const domains = SECTION_DOMAINS[section];
  const lang = SECTION_LANG[section];
  console.log(`\n=== ${section} (${lang}) ===`);
  for (const [domain, label] of Object.entries(domains)) {
    console.log(`  • ${label} (${domain})`);
  }

  const allArticles = [];
  const failedDomains = [];
  let first = isFirstOverall;
  for (const domain of Object.keys(domains)) {
    if (!first) await sleep(DELAY_MS);
    first = false;
    const articles = await fetchDomain(domain, lang);
    if (articles.length === 0) failedDomains.push(domains[domain]);
    console.log(`  ${String(articles.length).padStart(3)} articles  ${domains[domain]}`);
    allArticles.push(...articles);
  }

  // Cluster on shared entity phrases across outlets. This is the actual
  // signal: not "how many articles mention X" (one outlet often runs several
  // angles on its own story) but "how many *distinct* outlets are naming X
  // right now."
  const clusters = new Map();
  for (const article of allArticles) {
    const domainLabel = domains[article.domain] ?? article.domain;
    for (const phrase of extractPhrases(article.title)) {
      const key = phrase.toLowerCase();
      if (!clusters.has(key)) clusters.set(key, { phrase, domains: new Map() });
      const cluster = clusters.get(key);
      if (!cluster.domains.has(domainLabel)) cluster.domains.set(domainLabel, []);
      cluster.domains.get(domainLabel).push(article.title);
    }
  }

  const corroborated = [...clusters.values()]
    .filter((c) => c.domains.size >= 2)
    .sort(
      (a, b) =>
        b.domains.size - a.domains.size ||
        [...b.domains.values()].flat().length - [...a.domains.values()].flat().length
    );

  console.log(
    `\n${allArticles.length} articles, ${corroborated.length} phrase(s) named by 2+ outlets` +
      (failedDomains.length ? ` — no data from: ${failedDomains.join(", ")}` : "")
  );

  if (corroborated.length) {
    for (const cluster of corroborated.slice(0, 15)) {
      console.log(`\n${cluster.phrase}  —  ${cluster.domains.size} outlets`);
      for (const [domainLabel, titles] of cluster.domains) {
        console.log(`    ${domainLabel}: ${titles[0]}`);
      }
    }
  }

  return { section, articleCount: allArticles.length, corroboratedCount: corroborated.length };
}

const summaries = [];
let firstOverall = true;
for (const section of sectionsToRun) {
  summaries.push(await runSection(section, firstOverall));
  firstOverall = false;
}

console.log(`\n\n=== summary ===`);
for (const s of summaries) {
  console.log(
    `  ${s.section.padEnd(16)} ${String(s.articleCount).padStart(3)} articles, ` +
      `${s.corroboratedCount} corroborated`
  );
}
