// Tests of the Playwright projects of web/playwright.config.ts (Stories 0.8, 2.14, 2.16 and 4.1), listed through the npm scripts that
// the unit scripts call: which spec files each project runs (chromium runs every spec outside the directories that have a project of
// their own, demo-path/, demo-switch/ and floor/; each of those projects runs exactly its own directory; and every spec on disk is
// listed by at least one of the scripts), that every demo-path spec maps to a step of demo-path-summary.mjs, the
// form in which the report gives the floor test's tag, and that the floor script runs every floor case in Chromium and the cases tagged
// @browsers in Firefox and WebKit. Then one run of an API spec with none of the sign-in unit's variables.
// No browser starts and no stack is needed, none of the sign-in unit's OCUTALON_ variables is set, and the run writes its
// results to a scratch folder of its own, never to web/test-results.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { STEPS, stepOfFile } from './demo-path-summary.mjs';

const webDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const e2eDir = join(webDir, 'e2e');
const playwright = join(webDir, 'node_modules', '@playwright', 'test', 'cli.js');

const work = mkdtempSync(join(tmpdir(), 'ocutalon-ppt-'));
after(() => rmSync(work, { recursive: true, force: true }));

/** The environment of a run with no OCUTALON_ variable at all: no stack, no sign-in unit, no report. */
function bareEnv() {
  const env = { ...process.env };
  for (const name of Object.keys(env)) {
    if (name.startsWith('OCUTALON_')) delete env[name];
  }
  return env;
}

/** Every spec file under web/e2e/, relative to it and with `/`, as Playwright's default test match finds them. */
function specFilesOnDisk(dir = e2eDir, prefix = '') {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) found.push(...specFilesOnDisk(join(dir, entry.name), `${prefix}${entry.name}/`));
    else if (/\.(spec|test)\.[cm]?[jt]sx?$/.test(entry.name)) found.push(`${prefix}${entry.name}`);
  }
  return found.sort();
}

/** The JSON report of listing an npm script's tests, as the unit scripts run the script, without starting a browser. */
function listedReport(script) {
  const run = spawnSync('npm', ['--silent', '--prefix', webDir, 'run', script, '--', '--list', '--reporter=json'], {
    cwd: webDir,
    env: bareEnv(),
    encoding: 'utf8',
  });
  assert.equal(run.status, 0, run.stdout.slice(0, 500) + run.stderr.slice(0, 2000));
  return JSON.parse(run.stdout);
}

const listed = {};
/** The listing of an npm script, made once per run of this file. */
const reportOf = (script) => (listed[script] ??= listedReport(script));
/** The spec files that an npm script lists, in the config's own terms (relative to e2e/). */
const filesOf = (script) => reportOf(script).suites.map((suite) => suite.file).sort();

/**
 * The directories of web/e2e/ that have a project of their own; chromium runs everything else. A new directory goes here together
 * with its project in the config, its script in the list of the "every spec file on disk" case and an exact-listing case of its own.
 */
const OWN_PROJECT_DIRS = ['demo-path', 'demo-switch', 'floor'];
const inOwnProjectDir = (name) => OWN_PROJECT_DIRS.some((dir) => name.startsWith(`${dir}/`));

describe('the projects, listed with no OCUTALON_ variable set', () => {
  const onDisk = specFilesOnDisk();

  it('finds the sign-in, API, demo-path, demo-switch and floor specs on disk', () => {
    assert.ok(onDisk.some((name) => name.startsWith('sign-in/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('api/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('demo-path/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('demo-switch/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('floor/')), onDisk.join(' '));
  });

  it('chromium (the e2e script) lists exactly the spec files outside demo-path/, demo-switch/ and floor/', () => {
    assert.deepEqual(
      filesOf('e2e'),
      onDisk.filter((name) => !inOwnProjectDir(name)),
    );
  });

  it('demo-switch (the e2e:demo-switch script) lists exactly the spec files inside demo-switch/', () => {
    assert.deepEqual(
      filesOf('e2e:demo-switch'),
      onDisk.filter((name) => name.startsWith('demo-switch/')),
    );
  });

  it('every spec file on disk is listed by at least one of the chromium, demo-path, demo-switch and floor scripts', () => {
    const listedByAny = new Set(['e2e', 'e2e:demo-path', 'e2e:demo-switch', 'e2e:floor'].flatMap((script) => filesOf(script)));
    assert.deepEqual(onDisk.filter((name) => !listedByAny.has(name)), []);
  });

  it('floor (the e2e:floor script) lists exactly the spec files inside floor/', () => {
    assert.deepEqual(
      filesOf('e2e:floor'),
      onDisk.filter((name) => name.startsWith('floor/')),
    );
  });

  it('demo-path (the e2e:demo-path script) lists exactly the spec files inside demo-path/', () => {
    assert.deepEqual(
      filesOf('e2e:demo-path'),
      onDisk.filter((name) => name.startsWith('demo-path/')),
    );
  });

  it('demo-path lists the spec of every step, and no file that maps to no step', () => {
    const files = filesOf('e2e:demo-path');
    for (const [i, id] of STEPS.entries()) {
      assert.ok(files.includes(`demo-path/0${i + 1}-${id}.spec.ts`), `0${i + 1}-${id}.spec.ts is listed: ${files.join(' ')}`);
    }
    assert.deepEqual(files.filter((name) => stepOfFile(name).error), []);
  });

  it('reports the floor test of step 1 with the tag floor, the form that the summary reads', () => {
    const page = reportOf('e2e:demo-path').suites.find((suite) => suite.file === 'demo-path/01-page.spec.ts');
    const tagged = page.specs.filter((entry) => entry.tags.includes('floor'));
    assert.deepEqual(tagged.map((entry) => entry.title), [
      'signs in with the README account and loads the page snapshot',
      'shows the empty chat panel and the composer',
      'shows the status rail with its sections, counts and empty states',
    ]);
  });
});

/** Every spec of a listing, with its title, its tags and the projects that run it. */
function specsOf(report) {
  const found = [];
  const walk = (suite) => {
    for (const spec of suite.specs ?? []) {
      found.push({ file: spec.file, title: spec.title, tags: spec.tags, projects: spec.tests.map((one) => one.projectName) });
    }
    for (const child of suite.suites ?? []) walk(child);
  };
  report.suites.forEach(walk);
  return found;
}

describe('the floor script runs the floor in three engines (Story 2.16)', () => {
  const specs = specsOf(reportOf('e2e:floor'));
  const titlesOf = (project) => [...new Set(specs.filter((one) => one.projects.includes(project)).map((one) => `${one.file}: ${one.title}`))].sort();
  const unique = (list) => [...new Set(list)].sort();
  const tagged = unique(specs.filter((one) => one.tags.includes('browsers')).map((one) => `${one.file}: ${one.title}`));

  it('is the three floor projects, Chromium first', () => {
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:floor'];
    assert.equal(script, 'playwright test --project=floor --project=floor-firefox --project=floor-webkit');
    assert.deepEqual([...new Set(specs.flatMap((one) => one.projects))].sort(), ['floor', 'floor-firefox', 'floor-webkit']);
  });

  it('runs floor in Chromium, floor-firefox in Firefox and floor-webkit in WebKit, the last two on the @browsers cases', () => {
    const run = spawnSync(
      process.execPath,
      [
        '--no-warnings',
        '--input-type=module',
        '-e',
        "const { default: config } = await import('./playwright.config.ts'); console.log(JSON.stringify(config.projects.map((one) => [one.name, one.use?.defaultBrowserType, String(one.grep ?? '')])));",
      ],
      { cwd: webDir, env: bareEnv(), encoding: 'utf8' },
    );
    assert.equal(run.status, 0, run.stderr.slice(0, 2000));
    const projects = Object.fromEntries(JSON.parse(run.stdout).map(([name, engine, grep]) => [name, { engine, grep }]));
    assert.deepEqual(projects['floor'], { engine: 'chromium', grep: '' });
    assert.deepEqual(projects['floor-firefox'], { engine: 'firefox', grep: '/@browsers/' });
    assert.deepEqual(projects['floor-webkit'], { engine: 'webkit', grep: '/@browsers/' });
  });

  it('runs every floor test in floor, and the same @browsers tests in floor-firefox and floor-webkit', () => {
    assert.ok(titlesOf('floor').length >= 37, `floor lists ${titlesOf('floor').length} tests`);
    assert.deepEqual(titlesOf('floor'), [...new Set(specs.map((one) => `${one.file}: ${one.title}`))].sort());
    assert.ok(tagged.length > 0);
    assert.deepEqual(titlesOf('floor-firefox'), tagged);
    assert.deepEqual(titlesOf('floor-webkit'), tagged);
  });

  it('tags K1, K2 (the tooltip case), K4, G1, P2, A1, U1 to U4, E1 to E3, M1, M2, D1 and D6', () => {
    const ids = tagged.map((title) => /^[^:]+: ([A-Z]\d)/.exec(title)?.[1]);
    for (const id of ['K1', 'K2', 'K4', 'G1', 'P2', 'A1', 'U1', 'U2', 'U3', 'U4', 'E1', 'E2', 'E3', 'M1', 'M2', 'D1', 'D6']) {
      assert.ok(ids.includes(id), `${id} is tagged @browsers: ${tagged.join(' | ')}`);
    }
    assert.equal(ids.filter((id) => id === 'K2').length, 1, 'only the first K2 case is tagged');
    assert.ok(tagged.some((title) => /K2: Esc hides the tooltip first/.test(title)));
  });

  it('is run by neither the chromium script nor the demo-path script', () => {
    assert.deepEqual(filesOf('e2e').filter((name) => name.startsWith('floor/')), []);
    assert.deepEqual(filesOf('e2e:demo-path').filter((name) => name.startsWith('floor/')), []);
  });
});

describe('the API specs read the sign-in unit\'s variables when a test uses one', () => {
  it('fails a test that needs a missing variable, and names the variable', () => {
    // Row 18's trace-only test reads its user's variables before it sends a request, so it needs no browser and no stack.
    const run = spawnSync(
      process.execPath,
      [playwright, 'test', '--project=chromium', '-g', 'row 18: a trace-only user', '--output', join(work, 'row-18')],
      {
        cwd: webDir,
        env: { ...bareEnv(), OCUTALON_E2E_TIMEOUT_MS: '120000' },
        encoding: 'utf8',
      },
    );
    assert.equal(run.status, 1, run.stdout.slice(0, 500) + run.stderr.slice(0, 1000));
    assert.match(run.stdout.replace(/\u001b\[[0-9;]*m/g, ''), /^\s*1 failed$/m, 'exactly the one test ran, and it failed');
    assert.match(run.stdout + run.stderr, /OCUTALON_TRACEONLY_USER must be set by docker\/tests\/test-sign-in\.sh/);
  });
});
