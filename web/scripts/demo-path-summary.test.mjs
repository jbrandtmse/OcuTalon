// Tests of the demo-path summary (demo-path-summary.mjs): synthetic reports in the shape of Playwright 1.64.1's JSON report
// (a skip's text in annotations[].description, a tag without its @, one top-level suite per spec file), the command line's
// exit codes, and the real specs through Playwright (a run of the skipped tests, with its results in a scratch folder): no
// browser starts and no stack is needed. The listing of the real config is playwright-projects.test.mjs's.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { STEPS, stepOfFile, summarize, summarizeFile } from './demo-path-summary.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const webDir = join(here, '..');
const script = join(here, 'demo-path-summary.mjs');
const playwright = join(webDir, 'node_modules', '@playwright', 'test', 'cli.js');

const work = mkdtempSync(join(tmpdir(), 'ocutalon-dps-'));
after(() => rmSync(work, { recursive: true, force: true }));

// --- synthetic reports ---

const END_STATUS = { passed: 'expected', skipped: 'skipped', notRun: 'skipped' };

/** One spec with one test that ended as `result` (passed, skipped, failed, timedOut, interrupted or notRun). */
function spec(title, { tags = [], result = 'passed', annotations = [] } = {}) {
  return {
    title,
    ok: result === 'passed' || result === 'skipped',
    tags,
    file: 'demo-path/not-built.ts',
    tests: [
      {
        annotations,
        expectedStatus: result === 'skipped' || result === 'notRun' ? 'skipped' : 'passed',
        projectName: 'demo-path',
        results: result === 'notRun' ? [] : [{ status: result, annotations, errors: [] }],
        status: END_STATUS[result] ?? 'unexpected',
      },
    ],
  };
}

const floor = (result = 'passed') => spec('signs in with the README account and loads the page snapshot', { tags: ['floor'], result });
const skipText = (text) => [{ type: 'skip', description: text }];
const unbuilt = (title, story) => spec(title, { result: 'skipped', annotations: skipText(`Story ${story} turns this on`) });
const file = (name, specs, nested = []) => ({ title: `demo-path/${name}`, file: `demo-path/${name}`, column: 0, line: 0, specs, suites: nested });
const report = (suites, errors = []) => ({ suites, errors, stats: { expected: 0, skipped: 0, unexpected: 0, flaky: 0 } });

/** This story's report: one floor test and twelve unbuilt parts. */
function baseline() {
  return [
    file('01-page.spec.ts', [
      floor(),
      unbuilt('the chat panel and the composer', '2.5'),
      unbuilt('the simulated phone and the simulated mailbox, each labelled Simulated', '4.7'),
      unbuilt('the demo guide lists the steps, each with its one-click prompt', '4.7'),
      unbuilt('Break the feed is marked as a demo control', '4.7'),
    ]),
    file('02-watch.spec.ts', [unbuilt('the watch prompt gets its reply', '4.7'), unbuilt('the background check appears', '4.7'), unbuilt('the check row shows a real last run', '8.2')]),
    file('03-reminder.spec.ts', [unbuilt('the reminder prompt is confirmed', '4.7')]),
    file('04-incident.spec.ts', [unbuilt('one incident card awaits approval', '11.1'), unbuilt('the rail shows Approval requests (1)', '11.1')]),
    file('05-approval.spec.ts', [unbuilt('Approve on the simulated phone', '11.1')]),
    file('06-trace.spec.ts', [unbuilt('the trace link opens Visual Trace', '4.7')]),
  ];
}

/** The baseline with `change(suites)` applied to a copy. */
function changed(change) {
  const suites = structuredClone(baseline());
  change(suites);
  return suites;
}

const suiteOf = (suites, name) => suites.find((suite) => suite.file === `demo-path/${name}`);
const failuresOf = (suites, errors) => summarize(report(suites, errors)).failures;

// --- this story's report ---

describe('this story\'s report', () => {
  const { lines, failures } = summarize(report(baseline()));

  it('has no failure', () => {
    assert.deepEqual(failures, []);
  });

  it('reads step 1 as partly skipped and names the story of each skipped part', () => {
    assert.match(lines[0], /^STEP 1 page: partly skipped, 1 passed, 4 skipped \(Story 2\.5: the chat panel and the composer; Story 4\.7: /);
    assert.match(lines[0], /; Story 4\.7: Break the feed is marked as a demo control\)$/);
  });

  it('reads steps 2 to 6 as skipped, and no step as passed', () => {
    assert.match(lines[1], /^STEP 2 watch: skipped, 0 passed, 3 skipped \(Story 4\.7: .*; Story 8\.2: /);
    for (let i = 1; i < 6; i += 1) {
      assert.match(lines[i], new RegExp(`^STEP ${i + 1} ${STEPS[i]}: skipped, 0 passed, `));
    }
    assert.equal(lines.filter((line) => /^STEP \d \w+: passed/.test(line)).length, 0);
  });

  it('ends with the DEMO-PATH line', () => {
    assert.equal(lines.length, 7);
    assert.equal(lines[6], 'DEMO-PATH 1 of 6 steps ran (1 partly skipped), 12 skipped, 0 failed; floor 1 of 1 passed');
  });

  it('is exit 0 on the command line', () => {
    const path = join(work, 'baseline.json');
    writeFileSync(path, JSON.stringify(report(baseline())));
    const run = spawnSync(process.execPath, [script, path], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stdout + run.stderr);
    assert.equal(run.stdout.split('\n').filter((line) => line.startsWith('STEP ')).length, 6);
    assert.doesNotMatch(run.stdout, /^FAIL /m);
  });
});

describe('the verdicts', () => {
  it('reads a step of passed tests as passed, and a step of passed and skipped tests as partly skipped', () => {
    const suites = changed((s) => {
      suiteOf(s, '03-reminder.spec.ts').specs = [spec('the reminder prompt is confirmed')];
      suiteOf(s, '02-watch.spec.ts').specs.push(spec('the watch prompt gets its reply'));
    });
    const { lines, failures } = summarize(report(suites));
    assert.deepEqual(failures, []);
    assert.match(lines[2], /^STEP 3 reminder: passed, 1 passed, 0 skipped$/);
    assert.match(lines[1], /^STEP 2 watch: partly skipped, 1 passed, 3 skipped \(/);
    assert.match(lines[6], /^DEMO-PATH 3 of 6 steps ran \(2 partly skipped\), 11 skipped, 0 failed; floor 1 of 1 passed$/);
  });

  it('counts the tests of a describe block, however deep, and accepts a tag with its @', () => {
    const suites = changed((s) => {
      const page = suiteOf(s, '01-page.spec.ts');
      page.specs = page.specs.slice(1);
      page.suites = [{ title: 'outer', file: page.file, specs: [], suites: [{ title: 'inner', file: page.file, specs: [{ ...floor(), tags: ['@floor'] }] }] }];
    });
    const { lines, failures } = summarize(report(suites));
    assert.deepEqual(failures, []);
    assert.match(lines[0], /^STEP 1 page: partly skipped, 1 passed, 4 skipped /);
  });

  it('reads a step with a failed, a timed-out or an interrupted test as failed, and names the test', () => {
    for (const [result, words] of [['failed', 'failed'], ['timedOut', 'timed out'], ['interrupted', 'was interrupted'], ['notRun', 'did not run']]) {
      const suites = changed((s) => suiteOf(s, '02-watch.spec.ts').specs.push(spec('the watch prompt gets its reply', { result })));
      const { lines, failures } = summarize(report(suites));
      assert.match(lines[1], /^STEP 2 watch: failed, 0 passed, 3 skipped, 1 failed \(/, result);
      assert.deepEqual(failures, [`02-watch.spec.ts "the watch prompt gets its reply": ${words}`], result);
      assert.match(lines[6], /, 1 failed; floor 1 of 1 passed$/, result);
    }
  });
});

// --- row 5: a skip that names no story ---

describe('a skip without a story', () => {
  it('fails a plain skip, a skip with another text, a fixme and a skip whose text names no Story n.m', () => {
    const cases = [
      [{ type: 'skip', description: null }],
      skipText('not ready'),
      skipText('turns this on in Story 4.7'),
      skipText('Story 4 turns this on'),
      skipText('Story 4.7x turns this on'),
      [{ type: 'fixme', description: 'because' }],
      [{ type: 'fixme', description: null }],
    ];
    for (const annotations of cases) {
      const suites = changed((s) => suiteOf(s, '03-reminder.spec.ts').specs.push(spec('the reminder row appears', { result: 'skipped', annotations })));
      assert.deepEqual(failuresOf(suites), ['03-reminder.spec.ts "the reminder row appears": its skip names no story'], JSON.stringify(annotations));
    }
  });

  it('fails a skip that has no annotation at all', () => {
    const suites = changed((s) => suiteOf(s, '03-reminder.spec.ts').specs.push(spec('the reminder row appears', { result: 'skipped' })));
    assert.deepEqual(failuresOf(suites), ['03-reminder.spec.ts "the reminder row appears": its skip names no story']);
  });

  it('accepts a skip whose text starts with Story n.m, however it was written', () => {
    const suites = changed((s) =>
      suiteOf(s, '03-reminder.spec.ts').specs.push(
        spec('a', { result: 'skipped', annotations: [{ type: 'fixme', description: 'Story 12.4 turns this on' }] }),
        spec('b', { result: 'skipped', annotations: skipText('Story 10.3: created skipped') }),
      ),
    );
    const { lines, failures } = summarize(report(suites));
    assert.deepEqual(failures, []);
    assert.match(lines[2], /^STEP 3 reminder: skipped, 0 passed, 3 skipped \(Story 4\.7: .*; Story 12\.4: a; Story 10\.3: b\)$/);
  });
});

// --- row 6: the floor ---

describe('the floor', () => {
  it('fails a floor test that was skipped, failed, timed out or did not run', () => {
    for (const [result, words] of [['skipped', 'was skipped'], ['failed', 'failed'], ['timedOut', 'timed out'], ['notRun', 'did not run']]) {
      const annotations = result === 'skipped' ? skipText('Story 4.7 turns this on') : [];
      const suites = changed((s) => {
        suiteOf(s, '01-page.spec.ts').specs[0] = spec(floor().title, { tags: ['floor'], result, annotations });
      });
      const { lines, failures } = summarize(report(suites));
      assert.deepEqual(failures, ['floor test "signs in with the README account and loads the page snapshot" (01-page.spec.ts) ' + words], result);
      assert.match(lines[0], result === 'skipped' ? /^STEP 1 page: skipped, 0 passed, 5 skipped/ : /^STEP 1 page: failed, 0 passed, 4 skipped, 1 failed/, result);
      assert.match(lines[6], /; floor 0 of 1 passed$/, result);
    }
  });

  it('fails a floor test that was skipped with no story, with both reasons', () => {
    const suites = changed((s) => {
      suiteOf(s, '01-page.spec.ts').specs[0] = spec(floor().title, { tags: ['floor'], result: 'skipped', annotations: [{ type: 'skip', description: null }] });
    });
    const failures = failuresOf(suites);
    assert.equal(failures.length, 2);
    assert.ok(failures.some((failure) => failure.includes('its skip names no story')));
    assert.ok(failures.some((failure) => failure.startsWith('floor test ') && failure.endsWith('was skipped')));
  });

  it('fails a step 1 with no @floor test, and a floor test elsewhere is held to the same rule', () => {
    const none = changed((s) => (suiteOf(s, '01-page.spec.ts').specs = suiteOf(s, '01-page.spec.ts').specs.slice(1)));
    assert.deepEqual(failuresOf(none), ['step 1 page has no @floor test']);
    const elsewhere = changed((s) => suiteOf(s, '03-reminder.spec.ts').specs.push(spec('the reminder row appears', { tags: ['floor'], result: 'failed' })));
    assert.deepEqual(failuresOf(elsewhere), ['floor test "the reminder row appears" (03-reminder.spec.ts) failed']);
  });
});

// --- rows 7 and 8: the spec files ---

describe('the step specs', () => {
  it('fails a step whose spec is missing from the report, and names it', () => {
    const suites = changed((s) => s.splice(2, 1));
    const { lines, failures } = summarize(report(suites));
    assert.deepEqual(failures, ['step 3 reminder has no 03-reminder.spec.ts in the report']);
    assert.match(lines[2], /^STEP 3 reminder: failed, 0 passed, 0 skipped$/);
  });

  it('fails a step whose spec holds no test', () => {
    const suites = changed((s) => (suiteOf(s, '03-reminder.spec.ts').specs = []));
    assert.deepEqual(failuresOf(suites), ['step 3 reminder: 03-reminder.spec.ts holds no test']);
  });

  it('fails a spec file that maps to no step', () => {
    for (const name of ['07-extra.spec.ts', '02-reminder.spec.ts', 'extra.spec.ts', '1-page.spec.ts']) {
      const suites = changed((s) => s.push(file(name, [unbuilt('a part', '4.7')])));
      assert.deepEqual(failuresOf(suites), [`the report holds ${name}, which maps to no step`], name);
    }
  });

  it('counts a telegram part with its step', () => {
    const suites = changed((s) => s.push(file('telegram-watch.spec.ts', [unbuilt('the watch reply reaches Telegram', '12.4')])));
    const { lines, failures } = summarize(report(suites));
    assert.deepEqual(failures, []);
    assert.match(lines[1], /^STEP 2 watch: skipped, 0 passed, 4 skipped \(.*; Story 12\.4: the watch reply reaches Telegram\)$/);
    assert.match(lines[6], /, 13 skipped, 0 failed;/);
  });

  it('does not take a telegram part for the step\'s own spec', () => {
    const suites = changed((s) => {
      s.splice(2, 1);
      s.push(file('telegram-reminder.spec.ts', [unbuilt('the reminder reaches Telegram', '12.7')]));
    });
    assert.deepEqual(failuresOf(suites), ['step 3 reminder has no 03-reminder.spec.ts in the report']);
  });

  it('fails a telegram part of an unknown step', () => {
    const suites = changed((s) => s.push(file('telegram-nope.spec.ts', [unbuilt('a part', '12.4')])));
    assert.deepEqual(failuresOf(suites), ['the report holds telegram-nope.spec.ts, but nope is not a step (page, watch, reminder, incident, approval, trace)']);
  });

  it('maps a file by its name, whatever folder the report gives', () => {
    assert.deepEqual(stepOfFile('demo-path/04-incident.spec.ts'), { index: 3, numbered: true });
    assert.deepEqual(stepOfFile('e2e\\demo-path\\telegram-trace.spec.ts'), { index: 5, numbered: false });
    assert.ok(stepOfFile('demo-path/not-built.ts').error);
  });
});

// --- row 9: no usable report ---

describe('no usable report', () => {
  it('fails on every error that Playwright put in the report, such as a spec that failed to load or the global timeout', () => {
    const failures = failuresOf(baseline(), [{ message: '\u001b[31mSyntaxError: Unexpected token (2:6)\u001b[39m\n\n  1 | const = ;' }, { message: 'Timed out waiting 0.5s for the test suite to run' }]);
    assert.deepEqual(failures, ['Playwright reported an error: SyntaxError: Unexpected token (2:6)', 'Playwright reported an error: Timed out waiting 0.5s for the test suite to run']);
  });

  it('fails a report with no suites list, and says so without printing steps', () => {
    for (const bad of [{}, { suites: 'no' }, null, []]) {
      assert.deepEqual(summarize(bad), { lines: [], failures: ['no usable report: it holds no suites list'] });
    }
  });

  it('fails a report whose run found no spec: every step is missing', () => {
    const { lines, failures } = summarize(report([]));
    assert.equal(failures.length, 6);
    assert.ok(failures.every((failure) => /^step \d \w+ has no 0\d-\w+\.spec\.ts in the report$/.test(failure)));
    assert.equal(lines.filter((line) => /: failed, 0 passed, 0 skipped$/.test(line)).length, 6);
  });

  it('exits 1 with a FAIL line from the command line for a missing file, a file that is not JSON and a bad report', () => {
    const notJson = join(work, 'not-json.json');
    writeFileSync(notJson, 'Error: boom');
    const empty = join(work, 'empty.json');
    writeFileSync(empty, '{}');
    for (const [path, text] of [
      [join(work, 'does-not-exist.json'), /^FAIL no usable report: the file cannot be read \(ENOENT\)$/m],
      [notJson, /^FAIL no usable report: the file is not JSON/m],
      [empty, /^FAIL no usable report: it holds no suites list$/m],
    ]) {
      const run = spawnSync(process.execPath, [script, path], { encoding: 'utf8' });
      assert.equal(run.status, 1, run.stdout + run.stderr);
      assert.match(run.stdout, text);
      assert.doesNotMatch(run.stdout, /^STEP /m);
    }
    assert.equal(summarizeFile(notJson).failures.length, 1);
  });

  it('exits 1 from the command line for a failing report, with the STEP lines and the FAIL lines', () => {
    const path = join(work, 'failing.json');
    writeFileSync(path, JSON.stringify(report(changed((s) => (suiteOf(s, '01-page.spec.ts').specs[0] = floor('failed'))))));
    const run = spawnSync(process.execPath, [script, path], { encoding: 'utf8' });
    assert.equal(run.status, 1);
    assert.match(run.stdout, /^STEP 1 page: failed, 0 passed, 4 skipped, 1 failed /m);
    assert.match(run.stdout, /^DEMO-PATH 0 of 6 steps ran /m);
    assert.match(run.stdout, /^FAIL floor test "signs in with the README account and loads the page snapshot" \(01-page\.spec\.ts\) failed$/m);
  });

  it('is exit 2 without exactly one argument', () => {
    assert.equal(spawnSync(process.execPath, [script], { encoding: 'utf8' }).status, 2);
    assert.equal(spawnSync(process.execPath, [script, 'a', 'b'], { encoding: 'utf8' }).status, 2);
  });
});

// --- the real specs, through Playwright: no browser starts ---

/** The environment of a Playwright run: no report and no stack, whatever the shell holds. */
function playwrightEnv() {
  const env = { ...process.env, OCUTALON_E2E_TIMEOUT_MS: '120000' };
  delete env.OCUTALON_E2E_JSON;
  delete env.OCUTALON_URL;
  return env;
}

describe('the real specs, run without their floor test', () => {
  it('skip every unbuilt part with a story, so that each step reads skipped', () => {
    const json = join(work, 'real-specs.json');
    const run = spawnSync(
      process.execPath,
      [playwright, 'test', '--project=demo-path', '--grep-invert', '@floor', '--output', join(work, 'real-specs-results')],
      {
        cwd: webDir,
        env: { ...playwrightEnv(), OCUTALON_E2E_JSON: json },
        encoding: 'utf8',
      },
    );
    assert.equal(run.status, 0, run.stdout.slice(0, 500) + run.stderr.slice(0, 2000));
    // The list reporter runs beside the JSON report, so the unit's log names each skipped test.
    const printed = run.stdout.replace(/\u001b\[[0-9;]*m/g, '');
    assert.match(printed, /^\s*-\s+\d+ \[demo-path\] \u203a /m, printed.slice(0, 500));
    assert.match(printed, /^\s*\d+ skipped$/m, printed.slice(0, 500));
    const { lines, failures } = summarizeFile(json);
    // Every part of step 1 is a floor test (Story 4.7), so without the floor the step has no test in the report at all.
    assert.deepEqual(failures, ['step 1 page has no 01-page.spec.ts in the report']);
    for (const [i, id] of STEPS.entries()) {
      if (i === 0) continue;
      assert.match(lines[i], new RegExp(`^STEP ${i + 1} ${id}: skipped, 0 passed, [1-9]\\d* skipped \\(Story \\d+\\.\\d+: `));
    }
  });
});
