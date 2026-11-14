// Pins the built initial bundle (Story 36.5 QA; DW-1282): the Planner's binding target is an initial total of at most 921 kB (kB = 1,000 bytes, as the
// build's own table counts it; the measured total after Story 36.5 is 878.98 kB, the unchanged 1MB `maximumError` budget alone leaves a 120 kB gap).
// The test builds the app into a temporary folder (never src/ocutalon/csp/), with the chunk-optimizer flag that package.json's `build` script sets and no
// other NG_BUILD_* variable of the caller, and adds up the raw size of every file the page loads up front, as Angular counts its Initial total: the entry
// script and the stylesheet that the built index.html names, and every chunk they import statically, followed through the chunks (a dynamic `import(` is a
// lazy chunk and is not followed). It fails when enough code goes eager to pass 921 kB (the Settings page alone measured 978.35 kB); a smaller page going
// eager (History alone measured 899.79 kB) is the import-graph pin's to catch (lazy-routes.test.mjs).
// It also checks the built file names against the installer's STALEFILES pattern (live:bundle-folder) and that a main-*.js holds the About dialog's note
// (release/checklist.sh note-about).
// Takes about 20 s on a cold build and a few seconds with Angular's build cache (web/.angular) warm; in CI (CI=true) the cache is off, so it always builds cold.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const web = join(dirname(fileURLToPath(import.meta.url)), '..');
const MAX_INITIAL_BYTES = 921_000;
const ng = join(web, 'node_modules', '@angular', 'cli', 'bin', 'ng.js');

/** A chunk that a built script imports statically: `import{...}from"./chunk-X.js"`, `import"./chunk-X.js"` or `export{...}from"./chunk-X.js"`, never `import("./chunk-X.js")`. */
const STATIC_IMPORT = /\b(?:import|export)\s*(?:\{[^}]*\}\s*from\s*|\*\s*(?:as\s*[\w$]+\s*)?from\s*|[\w$]+\s*from\s*)?"\.\/([^"]+\.js)"/g;

/** The environment that the `build` script of package.json gives `ng build` (its `NAME=value` prefix), so the test builds what the script builds. */
function buildEnvironment() {
  const build = JSON.parse(readFileSync(join(web, 'package.json'), 'utf8')).scripts.build;
  const ngBuild = build.split('&&').pop().trim();
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('NG_BUILD_')));
  env.NG_CLI_ANALYTICS = 'false';
  for (const [, name, value] of ngBuild.matchAll(/(?:^|\s)([A-Z][A-Z0-9_]*)=(\S*)/g)) {
    env[name] = value;
  }
  return env;
}

/** The value of an attribute of an HTML tag. */
function attribute(tag, name) {
  return tag.match(new RegExp(`\\b${name}="([^"]+)"`))?.[1];
}

describe('the built initial bundle', () => {
  let out;
  let folder;

  before(() => {
    out = mkdtempSync(join(tmpdir(), 'ocutalon-initial-bundle-'));
    const built = spawnSync(process.execPath, [ng, 'build', `--output-path=${out}`], { cwd: web, env: buildEnvironment(), encoding: 'utf8', timeout: 300_000 });
    assert.equal(built.status, 0, `ng build succeeds:\n${built.stdout}\n${built.stderr}`);
    folder = existsSync(join(out, 'index.html')) ? out : join(out, 'browser');
  });

  after(() => {
    if (out) {
      rmSync(out, { recursive: true, force: true });
    }
  });

  it('holds at most 921 kB of files that the page loads up front', () => {
    const tags = [...readFileSync(join(folder, 'index.html'), 'utf8').matchAll(/<(?:link|script)\b[^>]*>/g)].map((match) => match[0]);
    const entries = tags.filter((tag) => tag.startsWith('<script') && attribute(tag, 'type') === 'module').map((tag) => attribute(tag, 'src'));
    const styles = [...new Set(tags.filter((tag) => attribute(tag, 'rel') === 'stylesheet').map((tag) => attribute(tag, 'href')))];
    const preloads = tags.filter((tag) => attribute(tag, 'rel') === 'modulepreload').map((tag) => attribute(tag, 'href'));
    assert.ok(entries.some((file) => /^main-.*\.js$/.test(file)), `index.html loads the entry script: ${entries.join(', ')}`);
    assert.ok(styles.some((file) => /^styles-.*\.css$/.test(file)), 'index.html loads the stylesheet');
    const scripts = new Set(entries);
    const queue = [...entries];
    while (queue.length > 0) {
      for (const match of readFileSync(join(folder, queue.pop()), 'utf8').matchAll(STATIC_IMPORT)) {
        if (!scripts.has(match[1])) {
          scripts.add(match[1]);
          queue.push(match[1]);
        }
      }
    }
    assert.deepEqual(preloads.filter((file) => !scripts.has(file)), [], 'every chunk index.html preloads is one the walk from the entry script found');
    const initial = [...scripts, ...styles];
    const total = initial.reduce((sum, file) => sum + statSync(join(folder, file)).size, 0);
    assert.ok(total <= MAX_INITIAL_BYTES, `the initial total is ${(total / 1000).toFixed(2)} kB, over the 921 kB target (${initial.join(', ')})`);
  });

  it('names every bundle file as the installer\'s STALEFILES pattern expects, and keeps the About note in a main-*.js', () => {
    const installer = readFileSync(join(web, '..', 'src', 'ocutalon', 'cls', 'OcuTalon', 'Install', 'Step', 'Web.cls'), 'utf8');
    const staleFiles = new RegExp(installer.match(/Parameter STALEFILES = "([^"]+)"/)[1]);
    const files = readdirSync(folder).filter((file) => /^(main|chunk|polyfills|styles)-/.test(file));
    assert.ok(files.length > 0, 'the build wrote bundle files');
    assert.deepEqual(files.filter((file) => !staleFiles.test(file)), [], 'every bundle file name matches STALEFILES');
    const note = readFileSync(join(web, 'src', 'app', 'about', 'about-dialog.ts'), 'utf8').match(/<p>(OcuTalon is inspired by [^<]+)<\/p>/)?.[1];
    assert.ok(note, 'the About dialog holds its note');
    assert.ok(
      files.some((file) => /^main-.*\.js$/.test(file) && readFileSync(join(folder, file), 'utf8').includes(note)),
      'a main-*.js holds the About note',
    );
  });
});
