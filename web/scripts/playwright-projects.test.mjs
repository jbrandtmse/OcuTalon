// Tests of the two Playwright projects of web/playwright.config.ts (Story 0.8), listed through the npm scripts that the unit
// scripts call: which spec files each project runs, that every demo-path spec maps to a step of demo-path-summary.mjs, and the
// form in which the report gives the floor test's tag. Then one run of an API spec with none of the sign-in unit's variables.
// No browser starts and no stack is needed, none of the sign-in unit's OCUTALON_ variables is set, and the run writes its
// results to a scratch folder of its own, never to web/test-results.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, rmSync } from 'node:fs';
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

describe('the projects, listed with no OCUTALON_ variable set', () => {
  const onDisk = specFilesOnDisk();

  it('finds the sign-in, API and demo-path specs on disk', () => {
    assert.ok(onDisk.some((name) => name.startsWith('sign-in/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('api/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('demo-path/')), onDisk.join(' '));
  });

  it('chromium (the e2e script) lists exactly the spec files outside demo-path/', () => {
    assert.deepEqual(
      filesOf('e2e'),
      onDisk.filter((name) => !name.startsWith('demo-path/')),
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
    assert.deepEqual(tagged.map((entry) => entry.title), ['signs in with the README account and loads the page snapshot']);
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
