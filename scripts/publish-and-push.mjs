#!/usr/bin/env node
/**
 * publish-and-push.mjs
 *
 * Called AFTER the edition JSON is written to docs/archive/YYYY-MM-DD.json.
 * Handles everything from photo-fetching through git push in a single shot,
 * so the Hermes agent only spends 1 tool call instead of ~8.
 *
 * Usage: node scripts/publish-and-push.mjs <edition-file>
 *
 * Exit codes:
 *   0 — published and pushed successfully
 *   1 — validation failed, edition NOT published (no git push)
 *   2 — validation passed, but something after (cp, prune, git) failed
 */

import { existsSync, readFileSync, cpSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { execSync } from 'node:child_process';

const editionFile = process.argv[2];
if (!editionFile) {
  console.error('Usage: node scripts/publish-and-push.mjs <edition-file>');
  process.exit(1);
}

if (!existsSync(editionFile)) {
  console.error(`Edition file not found: ${editionFile}`);
  process.exit(1);
}

const repoRoot = process.cwd();
const editionName = editionFile.replace(/^.*\//, '').replace(/\.json$/, '');
const dateStr = editionName;  // YYYY-MM-DD

console.log(`\n=== Publishing edition ${dateStr} ===\n`);

// ---- Step 1: Fetch and resize photos ----
console.log('1. Fetching photos...');
try {
  execSync(`node scripts/fetch-photos.mjs "${editionFile}"`, {
    stdio: 'inherit',
    cwd: repoRoot,
    timeout: 120_000,
  });
  console.log('   ✔ Photos fetched');
} catch (e) {
  console.error('   ⚠ fetch-photos had some failures (non-zero exit) — continuing');
}

// ---- Step 2: Validate the edition ----
console.log('2. Validating edition...');
let validationOutput;
try {
  validationOutput = execSync(
    `node scripts/validate.mjs "${editionFile}"`,
    { stdio: ['pipe', 'pipe', 'pipe'], cwd: repoRoot, timeout: 30_000, encoding: 'utf8' }
  );
  console.log('   ✔ Validation PASSED');
  console.log(validationOutput);
} catch (e) {
  validationOutput = e.stdout || '';
  const stderr = e.stderr || '';
  console.error('   ✘ Validation FAILED');
  console.error(stderr || validationOutput);
  process.exit(1);
}

// ---- Step 3: Copy to latest.json ----
console.log('3. Copying to latest.json...');
try {
  cpSync(editionFile, join(repoRoot, 'docs', 'latest.json'));
  console.log('   ✔ docs/latest.json updated');
} catch (e) {
  console.error('   ✘ Failed to copy to latest.json:', e.message);
  process.exit(2);
}

// ---- Step 4: Prune old photos ----
console.log('4. Pruning old photos...');
try {
  execSync('node scripts/prune-images.mjs', {
    stdio: 'inherit',
    cwd: repoRoot,
    timeout: 30_000,
  });
  console.log('   ✔ Photos pruned');
} catch (e) {
  console.error('   ⚠ prune-images.mjs had issues — continuing');
}

// ---- Step 5: Final validation ----
console.log('5. Final validation of latest.json...');
try {
  const finalValidation = execSync(
    'node scripts/validate.mjs',
    { stdio: ['pipe', 'pipe', 'pipe'], cwd: repoRoot, timeout: 30_000, encoding: 'utf8' }
  );
  console.log('   ✔ Final validation PASSED');
} catch (e) {
  console.error('   ⚠ Final validation warns — continuing to push');
  console.error(e.stdout || '');
}

// ---- Step 6: Git commit and push ----
console.log('6. Git operations...');
try {
  // Check if there's anything to commit
  const status = execSync('git status --porcelain', { cwd: repoRoot, encoding: 'utf8', timeout: 10_000 });
  if (!status.trim()) {
    console.log('   ℹ Nothing to commit — edition may already be up to date');
    process.exit(0);
  }

  execSync('git add -A', { stdio: 'inherit', cwd: repoRoot, timeout: 15_000 });
  console.log('   ✔ git add -A');

  execSync(`git commit -m "edition ${dateStr}"`, {
    stdio: 'inherit',
    cwd: repoRoot,
    timeout: 15_000,
  });
  console.log('   ✔ git commit');

  execSync('git push', { stdio: 'inherit', cwd: repoRoot, timeout: 60_000 });
  console.log('   ✔ git push');

  console.log(`\n=== Edition ${dateStr} published and pushed successfully! ===`);
} catch (e) {
  console.error('   ✘ Git operation failed:', e.message);
  process.exit(2);
}