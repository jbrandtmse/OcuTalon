// Tests of the Playwright projects of web/playwright.config.ts (Stories 0.8, 2.14, 2.16, 4.1, 6.3 and 6.4), listed through the npm scripts that
// the unit scripts call: which spec files each project runs (chromium runs every spec outside the directories that have a project of
// their own, demo-path/, demo-switch/, floor/, answers/ and cards/; each of those projects runs exactly its own directory; and every spec on
// disk is listed by at least one of the scripts), that every demo-path spec maps to a step of demo-path-summary.mjs, the
// form in which the report gives the floor test's tag, and that the floor script runs every floor case in Chromium and the cases tagged
// @browsers in Firefox and WebKit, and which cases each of the floor, answers and cards projects holds (Story 6.4, DW-315: the floor keeps I1
// and A1, the two incident and request cases tagged @browsers, the cards project holds the 19 cases that moved, and the answers project 6.3's
// and 6.4's own). Then one run of an API spec with none of the sign-in unit's variables.
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
const OWN_PROJECT_DIRS = ['demo-path', 'demo-switch', 'floor', 'answers', 'cards'];
const inOwnProjectDir = (name) => OWN_PROJECT_DIRS.some((dir) => name.startsWith(`${dir}/`));

/**
 * The folders of the sign-in-2 project (the sign-in-2 unit, docker/tests/test-sign-in-2.sh), split from the sign-in unit's chromium project
 * by spec file under the Contest Planner's ruling of 2026-11-05. The two projects together are the sign-in unit's spec set as it was: every
 * spec outside OWN_PROJECT_DIRS, each in exactly one of them.
 */
const SIGN_IN_2_DIRS = ['live', 'phone', 'rail', 'reminder', 'session', 'settings'];
const inSignIn2Dir = (name) => SIGN_IN_2_DIRS.some((dir) => name.startsWith(`${dir}/`));

/**
 * The folders and the root file of the sign-in-3 project (the sign-in-3 unit, docker/tests/test-sign-in-3.sh), split from the chromium project
 * by spec file under the Contest Planner's ruling of 2026-11-07. The three projects together are the sign-in unit's spec set: every spec
 * outside OWN_PROJECT_DIRS, each in exactly one of them.
 */
const SIGN_IN_3_DIRS = ['guide', 'heartbeat'];
const SIGN_IN_3_FILES = ['heartbeat-card.spec.ts', 'memory-noise.spec.ts', 'memory-card.spec.ts'];
const inSignIn3 = (name) => SIGN_IN_3_DIRS.some((dir) => name.startsWith(`${dir}/`)) || SIGN_IN_3_FILES.includes(name);

describe('the projects, listed with no OCUTALON_ variable set', () => {
  const onDisk = specFilesOnDisk();

  it('finds the sign-in, API, demo-path, demo-switch, floor, answers and cards specs on disk', () => {
    assert.ok(onDisk.some((name) => name.startsWith('sign-in/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('api/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('demo-path/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('demo-switch/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('floor/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('answers/')), onDisk.join(' '));
    assert.ok(onDisk.some((name) => name.startsWith('cards/')), onDisk.join(' '));
  });

  it('chromium (the e2e script) lists exactly the spec files outside demo-path/, demo-switch/, floor/, answers/, cards/, the folders of sign-in-2 and the folders and file of sign-in-3', () => {
    assert.deepEqual(
      filesOf('e2e'),
      onDisk.filter((name) => !inOwnProjectDir(name) && !inSignIn2Dir(name) && !inSignIn3(name)),
    );
  });

  it('sign-in-2 (the e2e:sign-in-2 script) lists exactly the spec files inside live/, phone/, rail/, reminder/, session/ and settings/', () => {
    assert.deepEqual(
      filesOf('e2e:sign-in-2'),
      onDisk.filter((name) => inSignIn2Dir(name)),
    );
    for (const dir of SIGN_IN_2_DIRS) assert.ok(filesOf('e2e:sign-in-2').some((name) => name.startsWith(`${dir}/`)), `${dir}/ holds a spec`);
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:sign-in-2'];
    assert.equal(script, 'playwright test --project=sign-in-2');
  });

  it('sign-in-3 (the e2e:sign-in-3 script) lists exactly the spec files inside guide/ and heartbeat/ and the files heartbeat-card.spec.ts, memory-noise.spec.ts and memory-card.spec.ts', () => {
    assert.deepEqual(
      filesOf('e2e:sign-in-3'),
      onDisk.filter((name) => inSignIn3(name)),
    );
    for (const dir of SIGN_IN_3_DIRS) assert.ok(filesOf('e2e:sign-in-3').some((name) => name.startsWith(`${dir}/`)), `${dir}/ holds a spec`);
    for (const file of SIGN_IN_3_FILES) {
      assert.ok(onDisk.includes(file), `${file} exists`);
      assert.ok(filesOf('e2e:sign-in-3').includes(file), `${file} is listed`);
    }
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:sign-in-3'];
    assert.equal(script, 'playwright test --project=sign-in-3');
  });

  it('the three sign-in units, chromium, sign-in-2 and sign-in-3, share no spec file and together list every spec outside the other projects\' folders', () => {
    const chromium = filesOf('e2e');
    const second = filesOf('e2e:sign-in-2');
    const third = filesOf('e2e:sign-in-3');
    assert.ok(chromium.length > 0 && second.length > 0 && third.length > 0, 'each unit runs a spec');
    assert.deepEqual(chromium.filter((name) => second.includes(name) || third.includes(name)), [], 'no spec file runs in both chromium and another unit');
    assert.deepEqual(second.filter((name) => third.includes(name)), [], 'no spec file runs in both sign-in-2 and sign-in-3');
    assert.deepEqual([...chromium, ...second, ...third].sort(), onDisk.filter((name) => !inOwnProjectDir(name)), 'every spec of the sign-in set runs in one of them');
    // And test by test, as Playwright lists them (a test is its file, line, column and title, since titles repeat across describe blocks):
    // each unit runs its tests in one project, and no test is listed by both.
    const testsOf = (script) => {
      const found = [];
      const walk = (suite) => {
        for (const spec of suite.specs ?? []) for (const one of spec.tests) found.push({ key: `${spec.file}:${spec.line}:${spec.column} ${spec.title}`, project: one.projectName });
        for (const child of suite.suites ?? []) walk(child);
      };
      reportOf(script).suites.forEach(walk);
      return found;
    };
    assert.deepEqual([...new Set(testsOf('e2e').map((one) => one.project))], ['chromium']);
    assert.deepEqual([...new Set(testsOf('e2e:sign-in-2').map((one) => one.project))], ['sign-in-2']);
    assert.deepEqual([...new Set(testsOf('e2e:sign-in-3').map((one) => one.project))], ['sign-in-3']);
    const all = [...testsOf('e2e'), ...testsOf('e2e:sign-in-2'), ...testsOf('e2e:sign-in-3')].map((one) => one.key);
    assert.equal(new Set(all).size, all.length, 'no test is listed by two units');
  });

  it('demo-switch (the e2e:demo-switch script) lists exactly the spec files inside demo-switch/', () => {
    assert.deepEqual(
      filesOf('e2e:demo-switch'),
      onDisk.filter((name) => name.startsWith('demo-switch/')),
    );
  });

  it('answers (the e2e:answers script) lists exactly the spec files inside answers/, and the chromium script none of them', () => {
    assert.deepEqual(
      filesOf('e2e:answers'),
      onDisk.filter((name) => name.startsWith('answers/')),
    );
    assert.ok(filesOf('e2e:answers').length > 0, 'the answers project has a spec');
    assert.deepEqual(filesOf('e2e').filter((name) => name.startsWith('answers/')), []);
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:answers'];
    assert.equal(script, 'playwright test --project=answers');
  });

  it('cards (the e2e:cards script) lists exactly the spec files inside cards/, and the chromium script none of them', () => {
    assert.deepEqual(
      filesOf('e2e:cards'),
      onDisk.filter((name) => name.startsWith('cards/')),
    );
    assert.ok(filesOf('e2e:cards').length > 0, 'the cards project has a spec');
    assert.deepEqual(filesOf('e2e').filter((name) => name.startsWith('cards/')), []);
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:cards'];
    assert.equal(script, 'playwright test --project=cards');
  });

  it('rehearsal (the e2e:rehearsal script, Story 11.12) lists exactly the specs of e2e-rehearsal/ in run order, and the chromium script none of them', () => {
    const own = readdirSync(join(webDir, 'e2e-rehearsal')).filter((name) => /\.spec\.ts$/.test(name)).sort();
    assert.deepEqual(own, ['repeat.spec.ts', 'tell-now.spec.ts']);
    assert.deepEqual(filesOf('e2e:rehearsal'), own.map((name) => `../e2e-rehearsal/${name}`));
    assert.deepEqual(filesOf('e2e').filter((name) => name.includes('e2e-rehearsal')), []);
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:rehearsal'];
    assert.equal(script, 'playwright test --config=playwright.rehearsal.config.ts');
  });

  it('every spec file on disk is listed by at least one of the chromium, sign-in-2, sign-in-3, demo-path, demo-switch, floor, answers and cards scripts', () => {
    const listedByAny = new Set(['e2e', 'e2e:sign-in-2', 'e2e:sign-in-3', 'e2e:demo-path', 'e2e:demo-switch', 'e2e:floor', 'e2e:answers', 'e2e:cards'].flatMap((script) => filesOf(script)));
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
      'the simulated phone and the simulated mailbox, each labelled Simulated',
      'the demo guide lists the steps, each with its one-click prompt',
      'Break the feed is marked as a demo control',
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

  it('tags K1, K2 (the tooltip case), K4, G1, P2, A1, U1 to U4, E1 to E4, M1, M2, D1 and D6', () => {
    const ids = tagged.map((title) => /^[^:]+: ([A-Z]\d)/.exec(title)?.[1]);
    for (const id of ['K1', 'K2', 'K4', 'G1', 'P2', 'A1', 'U1', 'U2', 'U3', 'U4', 'E1', 'E2', 'E3', 'E4', 'M1', 'M2', 'D1', 'D6']) {
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

describe('the case lists of the floor, answers and cards projects (Story 6.4; DW-315)', () => {
  const idOf = (title) => /^([A-Z]\d+):/.exec(title)?.[1];
  const floor = specsOf(reportOf('e2e:floor')).filter((one) => one.projects.includes('floor'));
  const answers = specsOf(reportOf('e2e:answers'));
  const cards = specsOf(reportOf('e2e:cards'));
  const range = (letter, from, to) => Array.from({ length: to - from + 1 }, (_, i) => `${letter}${from + i}`);

  it('keeps I1 and A1 in the floor, and none of the cases that moved', () => {
    const files = (name) => floor.filter((one) => one.file === name);
    const ids = (name) => files(name).map((one) => `${one.file}: ${idOf(one.title)}`);
    assert.deepEqual(ids('floor/incident.spec.ts'), ['floor/incident.spec.ts: I1']);
    assert.deepEqual(ids('floor/approval.spec.ts'), ['floor/approval.spec.ts: A1']);
    const floorIds = floor.map((one) => idOf(one.title));
    for (const moved of [...range('I', 2, 11), ...range('A', 2, 10)]) {
      assert.ok(!floor.some((one) => one.file.startsWith('floor/') && /^floor\/(incident|approval)\.spec\.ts$/.test(one.file) && idOf(one.title) === moved), `${moved} is not in the floor's incident and approval specs`);
    }
    assert.ok(floorIds.includes('I1') && floorIds.includes('A1'));
    assert.ok(files('floor/incident.spec.ts')[0].tags.includes('browsers') && files('floor/approval.spec.ts')[0].tags.includes('browsers'), 'I1 and A1 are the @browsers cases');
  });

  it('runs I1 and A1 in all three engines', () => {
    for (const project of ['floor', 'floor-firefox', 'floor-webkit']) {
      const ids = specsOf(reportOf('e2e:floor')).filter((one) => one.projects.includes(project) && /^floor\/(incident|approval)\.spec\.ts$/.test(one.file)).map((one) => idOf(one.title));
      assert.deepEqual(ids.sort(), ['A1', 'I1'], project);
    }
  });

  it('holds I2 to I11, A2 to A13 and E1 to E6 in the cards project, each once and in its own spec', () => {
    const where = (id) => cards.filter((one) => idOf(one.title) === id).map((one) => one.file);
    for (const id of range('I', 2, 11)) assert.deepEqual(where(id), ['cards/incident-card.spec.ts'], id);
    for (const id of range('A', 2, 13)) assert.deepEqual(where(id), ['cards/approval-card.spec.ts'], id);
    for (const id of range('E', 1, 8)) assert.deepEqual(where(id), ['cards/either-way.spec.ts'], id);
    assert.equal(cards.length, 30, 'and no other case');
    assert.deepEqual([...new Set(cards.flatMap((one) => one.projects))], ['cards'], 'in Chromium only: no case is tagged for Firefox or WebKit');
  });

  it('holds X1 to X13 and C1 to C10 in the answers project, each once and in its own spec', () => {
    const where = (id) => answers.filter((one) => idOf(one.title) === id).map((one) => one.file);
    for (const id of range('X', 1, 13)) assert.deepEqual(where(id), ['answers/answers.spec.ts'], id);
    for (const id of range('C', 1, 10)) assert.deepEqual(where(id), ['answers/close-loop.spec.ts'], id);
    assert.equal(answers.length, 23, 'and no other case');
    assert.deepEqual([...new Set(answers.flatMap((one) => one.projects))], ['answers'], 'in Chromium only: no case is tagged for Firefox or WebKit');
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

describe('the online-demo, online-session, online-allowance, online-demo-path and online-visitors projects (Stories 16.1, 16.4, 16.9, 29.4 and 29.7)', () => {
  const onlineOnDisk = specFilesOnDisk(join(webDir, 'e2e-online'));
  // The listing names a file relative to the config's own testDir (e2e/), so these projects' files start with ../e2e-online/.
  const listedName = (name) => `../e2e-online/${name}`;
  const inOwnFolder = (name) => name.startsWith('session/') || name.startsWith('allowance/') || name.startsWith('demo-path/') || name.startsWith('visitors/');

  it('online-demo (the e2e:online-demo script) lists exactly the spec files of web/e2e-online/ outside session/, allowance/, demo-path/ and visitors/', () => {
    assert.ok(onlineOnDisk.length > 0, 'web/e2e-online/ holds spec files');
    assert.deepEqual(
      filesOf('e2e:online-demo'),
      onlineOnDisk.filter((name) => !inOwnFolder(name)).map(listedName),
    );
  });

  it('online-session (the e2e:online-session script) lists exactly the spec files of web/e2e-online/session/, and the online-demo script none of them', () => {
    const own = onlineOnDisk.filter((name) => name.startsWith('session/'));
    assert.ok(own.length > 0, 'web/e2e-online/session/ holds spec files');
    // This project's testDir is e2e-online/session/, so its files are named relative to it.
    assert.deepEqual(
      filesOf('e2e:online-session'),
      own.map((name) => `../e2e-online/${name}`),
    );
    assert.deepEqual(filesOf('e2e:online-demo').filter((name) => name.startsWith(listedName('session/'))), []);
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:online-session'];
    assert.equal(script, 'playwright test --project=online-session');
  });

  it('online-allowance (the e2e:online-allowance script) lists exactly the spec files of web/e2e-online/allowance/, and the online-demo script none of them', () => {
    const own = onlineOnDisk.filter((name) => name.startsWith('allowance/'));
    assert.deepEqual(own, ['allowance/daily-cap.spec.ts', 'allowance/memory-search.spec.ts', 'allowance/messages.spec.ts'], 'web/e2e-online/allowance/ holds the two specs of Story 16.9 and the Memory card search spec of Story 41.13');
    assert.deepEqual(
      filesOf('e2e:online-allowance'),
      own.map((name) => `../e2e-online/${name}`),
    );
    assert.deepEqual(filesOf('e2e:online-demo').filter((name) => name.startsWith(listedName('allowance/'))), []);
    assert.deepEqual(filesOf('e2e:online-session').filter((name) => name.includes('allowance')), []);
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:online-allowance'];
    assert.equal(script, 'playwright test --project=online-allowance');
  });

  it('online-demo-path (the e2e:online-demo-path script) lists exactly the spec files of web/e2e-online/demo-path/, and the online-demo script none of them', () => {
    const own = onlineOnDisk.filter((name) => name.startsWith('demo-path/'));
    assert.deepEqual(own, ['demo-path/demo-path.spec.ts'], 'web/e2e-online/demo-path/ holds the online run of Story 29.4');
    assert.deepEqual(
      filesOf('e2e:online-demo-path'),
      own.map((name) => `../e2e-online/${name}`),
    );
    assert.deepEqual(filesOf('e2e:online-demo').filter((name) => name.includes('demo-path')), []);
    assert.deepEqual(filesOf('e2e:online-session').filter((name) => name.includes('demo-path')), []);
    assert.deepEqual(filesOf('e2e:online-allowance').filter((name) => name.includes('demo-path')), []);
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:online-demo-path'];
    assert.equal(script, 'playwright test --project=online-demo-path');
  });

  it('online-visitors (the e2e:online-visitors script) lists exactly the spec files of web/e2e-online/visitors/, and the other online scripts none of them', () => {
    const own = onlineOnDisk.filter((name) => name.startsWith('visitors/'));
    assert.deepEqual(own, ['visitors/visitors.spec.ts'], 'web/e2e-online/visitors/ holds the visitor count case of Story 29.7');
    assert.deepEqual(
      filesOf('e2e:online-visitors'),
      own.map((name) => `../e2e-online/${name}`),
    );
    for (const script of ['e2e:online-demo', 'e2e:online-session', 'e2e:online-allowance', 'e2e:online-demo-path']) {
      assert.deepEqual(filesOf(script).filter((name) => name.includes('visitors')), [], script);
    }
    const script = JSON.parse(readFileSync(join(webDir, 'package.json'), 'utf8')).scripts['e2e:online-visitors'];
    assert.equal(script, 'playwright test --project=online-visitors');
  });

  it('every spec file of web/e2e-online/ is listed by one of the five scripts, and by neither e2e script of web/e2e/', () => {
    const listedByAny = new Set([
      ...filesOf('e2e:online-demo'),
      ...filesOf('e2e:online-session'),
      ...filesOf('e2e:online-allowance'),
      ...filesOf('e2e:online-demo-path'),
      ...filesOf('e2e:online-visitors'),
    ]);
    assert.deepEqual(onlineOnDisk.map(listedName).filter((name) => !listedByAny.has(name)), []);
    assert.deepEqual(filesOf('e2e').filter((name) => name.includes('e2e-online')), []);
  });
});
