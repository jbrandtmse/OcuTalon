// Tests of the part cut of the sign-in unit (e2e-part.mjs): synthetic listings in the shape of Playwright 1.64.1's JSON listing
// (one top-level suite per spec file, tests in specs, nested suites counted too), the command line's exit codes, and the real
// listing of the chromium project, made the way docker/tests/test-sign-in.sh makes it. No stack and no browser start.
// The hosted web job runs these tests, so WEB_INPUT_PATTERN of ci/units.sh must match the sign-in script they read and run: the
// last block pins that, applying the pattern the way ci/changes.sh applies it.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { describePart, parsePart, partOf } from './e2e-part.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const webDir = join(here, '..');
const script = join(here, 'e2e-part.mjs');

const work = mkdtempSync(join(tmpdir(), 'ocutalon-e2e-part-'));
after(() => rmSync(work, { recursive: true, force: true }));

// --- synthetic listings ---

const specOf = (title) => ({ title, ok: true, tags: [], tests: [{ projectName: 'chromium', results: [], status: 'skipped' }] });

/** A listing of files f01.spec.ts, f02.spec.ts, ... holding `counts[i]` tests; the first spec of a file sits in a nested suite. */
function listing(counts) {
  return {
    config: {},
    suites: counts.map((count, index) => {
      const file = `d${index % 3}/f${String(index + 1).padStart(2, '0')}.spec.ts`;
      const specs = Array.from({ length: count }, (_, test) => specOf(`t${test}`));
      return { title: file, file, specs: specs.slice(1), suites: count > 0 ? [{ title: 'group', specs: specs.slice(0, 1) }] : [] };
    }),
    errors: [],
  };
}

const TODAY = [20, 19, 20, 14, 15, 20, 18, 1, 14, 6, 19, 2, 2, 9, 5, 15, 19, 4];
const sum = (values) => values.reduce((a, b) => a + b, 0);
const namesOf = (part) => part.files.map((entry) => entry.file);
const testsOf = (part) => sum(part.files.map((entry) => entry.tests));

/** The parts of every k for one n, or the string 'empty' for a part that is refused as empty. */
function allParts(report, n) {
  const parts = [];
  for (let k = 1; k <= n; k += 1) {
    try {
      parts.push(partOf(report, k, n));
    } catch (error) {
      if (/holds no spec file/.test(error.message)) parts.push('empty');
      else throw error;
    }
  }
  return parts;
}

/** The invariants of AC 1 for a listing and an n: the parts, put together, are the listing, each file once and whole. */
function assertCovers(report, n) {
  const names = report.suites.map((suite) => suite.file);
  const total = sum(report.suites.map((suite) => (suite.specs?.length ?? 0) + sum((suite.suites ?? []).map((child) => child.specs.length))));
  const parts = allParts(report, n);
  const taken = parts.filter((part) => part !== 'empty');
  assert.deepEqual(taken.flatMap(namesOf), names, `n=${n}: the parts together are the listing's files in order, each once`);
  assert.equal(sum(taken.map(testsOf)), total, `n=${n}: the parts' tests add up to the listing's`);
  // Each file sits in the part whose range holds its first test.
  const size = Math.floor(total / n);
  const larger = total % n;
  let first = 0;
  for (const suite of report.suites) {
    const tests = (suite.specs?.length ?? 0) + sum((suite.suites ?? []).map((child) => child.specs.length));
    let k = 1;
    let start = 0;
    while (k < n && first >= start + size + (k <= larger ? 1 : 0)) {
      start += size + (k <= larger ? 1 : 0);
      k += 1;
    }
    const where = parts.findIndex((part) => part !== 'empty' && namesOf(part).includes(suite.file));
    assert.equal(where + 1, k, `n=${n}: ${suite.file} (first test ${first}) is in part ${k}`);
    first += tests;
  }
}

describe('parsePart', () => {
  it('reads k/n with 1 <= k <= n', () => {
    assert.deepEqual(parsePart('1/2'), { k: 1, n: 2 });
    assert.deepEqual(parsePart('18/18'), { k: 18, n: 18 });
    assert.deepEqual(parsePart('000001/000002'), { k: 1, n: 2 });
  });

  it('refuses every malformed or out-of-range value, naming it', () => {
    for (const bad of ['', 'x', '0/2', '3/2', '1/0', '1/2/3', '1/', '/2', '-1/2', '1/-2', ' 1/2', '1/2 ', '1.5/2', '1/1234567', '+1/2']) {
      assert.throws(() => parsePart(bad), (error) => error.message.includes(`'${bad}'`), `'${bad}'`);
    }
  });
});

describe('partOf, on synthetic listings', () => {
  it("cuts today's counts in two: 7 files and 126 tests, then 11 files and 96 tests", () => {
    const report = listing(TODAY);
    const one = partOf(report, 1, 2);
    const two = partOf(report, 2, 2);
    assert.deepEqual([one.files.length, testsOf(one)], [7, 126]);
    assert.deepEqual([two.files.length, testsOf(two)], [11, 96]);
    assert.deepEqual([one.totalFiles, one.totalTests], [18, 222]);
  });

  it('gives file 1 to part 1 and file 2 to part 2 for two files of two tests', () => {
    const report = listing([2, 2]);
    assert.deepEqual(namesOf(partOf(report, 1, 2)), [report.suites[0].file]);
    assert.deepEqual(namesOf(partOf(report, 2, 2)), [report.suites[1].file]);
  });

  it('puts the parts together into the listing, each file once, for every n from 1 to the file count', () => {
    for (const counts of [TODAY, [2, 2], [1, 1, 1], [5, 1, 1, 1, 5], [3, 3, 3, 3, 3, 3], [1, 2, 3, 4, 5, 6, 7], [10, 1, 1], [1, 1, 10], [4, 0, 4], [0, 3, 0, 3], [3, 3, 0], [3, 0, 0], [2, 4, 0, 0]]) {
      const report = listing(counts);
      for (let n = 1; n <= counts.length; n += 1) assertCovers(report, n);
    }
  });

  it('keeps a file whole, in the part of its first test, when its tests cross a range end', () => {
    // 10 tests, n = 2: the ranges are [0,5) and [5,10); the first file's tests cross 5.
    const report = listing([8, 1, 1]);
    assert.deepEqual(namesOf(partOf(report, 1, 2)), [report.suites[0].file]);
    assert.deepEqual(namesOf(partOf(report, 2, 2)), [report.suites[1].file, report.suites[2].file]);
  });

  it('gives the files with no test after the last test to the last part', () => {
    const report = listing([3, 3, 0]);
    assert.deepEqual(namesOf(partOf(report, 1, 2)), [report.suites[0].file]);
    assert.deepEqual(namesOf(partOf(report, 2, 2)), [report.suites[1].file, report.suites[2].file]);
  });

  it('sizes the ranges to differ by at most one, the first T mod n being the larger', () => {
    // 7 tests in 7 files, n = 3: ranges of 3, 2 and 2.
    const report = listing([1, 1, 1, 1, 1, 1, 1]);
    assert.deepEqual([1, 2, 3].map((k) => partOf(report, k, 3).files.length), [3, 2, 2]);
  });

  it('refuses part 2 of [1,100] as empty, and n above the file count', () => {
    assert.throws(() => partOf(listing([1, 100]), 2, 2), /part 2\/2 holds no spec file, so use fewer parts/);
    assert.throws(() => partOf(listing([1, 100]), 1, 3), /holds 2 spec files/);
    assert.throws(() => partOf(listing(TODAY), 19, 19), /holds 18 spec files/);
  });

  it('refuses a listing with errors or with no suites as a broken listing', () => {
    assert.throws(() => partOf({ suites: [], errors: [] }, 1, 1), /no spec files/);
    assert.throws(() => partOf({ errors: [] }, 1, 1), /no spec files/);
    assert.throws(() => partOf({ ...listing([1]), errors: [{ message: 'boom' }] }, 1, 1), /boom/);
  });
});

// --- the command line ---

function cli(args) {
  return spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
}

function listingFile(name, content) {
  const path = join(work, name);
  writeFileSync(path, typeof content === 'string' ? content : JSON.stringify(content));
  return path;
}

describe('the command line', () => {
  const today = listingFile('today.json', listing(TODAY));

  it('prints the PART line, then one file per line', () => {
    const run = cli(['2/2', today]);
    assert.equal(run.status, 0, run.stderr);
    const lines = run.stdout.trimEnd().split('\n');
    assert.match(lines[0], /^PART 2\/2: 11 of 18 spec files, 96 of 222 tests: d1\/f08\.spec\.ts .* d2\/f18\.spec\.ts$/);
    assert.equal(lines.length, 1 + 11);
    assert.equal(lines[1], 'd1/f08.spec.ts');
  });

  it('exits 2 with one line naming the value, for every bad value of the matrix', () => {
    for (const bad of ['', 'x', '0/2', '3/2', '1/0', '1/2/3', '19/19']) {
      const run = cli([bad, today]);
      assert.equal(run.status, 2, `'${bad}'`);
      assert.equal(run.stdout, '');
      assert.equal(run.stderr.trimEnd().split('\n').length, 1, `'${bad}': one line`);
      assert.ok(run.stderr.includes(bad === '19/19' ? '19/19' : `'${bad}'`), `'${bad}' is named: ${run.stderr}`);
    }
  });

  it('exits 2 for an empty part, and 2 for a wrong number of arguments', () => {
    const run = cli(['2/2', listingFile('lopsided.json', listing([1, 100]))]);
    assert.equal(run.status, 2);
    assert.match(run.stderr, /holds no spec file/);
    assert.equal(cli([]).status, 2);
    assert.equal(cli(['1/2']).status, 2);
    assert.equal(cli(['1/2', today, 'extra']).status, 2);
  });

  it('exits 1 for a missing, unreadable, non-JSON or broken listing', () => {
    assert.equal(cli(['1/2', join(work, 'missing.json')]).status, 1);
    assert.equal(cli(['1/2', work]).status, 1);
    assert.equal(cli(['1/2', listingFile('text.json', 'Error: a spec failed to load')]).status, 1);
    assert.equal(cli(['1/2', listingFile('empty.json', { suites: [], errors: [] })]).status, 1);
    const broken = cli(['1/2', listingFile('errors.json', { ...listing([1, 1]), errors: [{ message: 'SyntaxError in a.spec.ts' }] })]);
    assert.equal(broken.status, 1);
    assert.match(broken.stderr, /SyntaxError in a\.spec\.ts/);
  });
});

/** The environment of a run with no OCUTALON_ variable at all, as playwright-projects.test.mjs makes its listings. */
function bareEnv() {
  const env = { ...process.env };
  for (const name of Object.keys(env)) {
    if (name.startsWith('OCUTALON_')) delete env[name];
  }
  return env;
}

// --- the unit's arguments: a bad one ends the script before its lock, its bundle build and any stack ---

describe('docker/tests/test-sign-in.sh, given a bad argument', () => {
  const unit = join(here, '..', '..', 'docker', 'tests', 'test-sign-in.sh');
  // Each bad argument, with the text its one line names. The n of 999999/999999 is above any listing's file count, so that the
  // case is refused whatever spec files the project holds.
  const bad = [
    [['--bogus'], "'--bogus'"],
    [['--part'], '--part needs one value'],
    [['--part='], "''"],
    [['--part', 'x'], "'x'"],
    [['--part=0/2'], "'0/2'"],
    [['--part', '3/2'], "'3/2'"],
    [['--part=999999/999999'], '999999/999999'],
    [['--part', '1/2', '--part', '2/2'], "'2/2'"],
  ];

  for (const [args, named] of bad) {
    it(`exits 2 with one line naming the value and no LOCK line for ${args.join(' ')}`, () => {
      const run = spawnSync('bash', [unit, ...args], { env: bareEnv(), encoding: 'utf8' });
      assert.equal(run.status, 2, run.stdout + run.stderr);
      const lines = (run.stdout + run.stderr).split('\n').filter((line) => line !== '');
      assert.equal(lines.length, 1, `one line: ${lines.join(' | ')}`);
      assert.ok(lines[0].includes(named), `the line names ${named}: ${lines[0]}`);
      assert.ok(!/LOCK/.test(run.stdout + run.stderr));
    });
  }
});

// --- the real listing, as test-sign-in.sh makes it ---

describe('the real listing of the chromium project', () => {
  const run = spawnSync('npm', ['--silent', '--prefix', webDir, 'run', 'e2e', '--', '--list', '--reporter=json'], { cwd: webDir, env: bareEnv(), encoding: 'utf8' });
  assert.equal(run.status, 0, run.stdout.slice(0, 500) + run.stderr.slice(0, 2000));
  const report = JSON.parse(run.stdout);
  const real = listingFile('real.json', run.stdout);
  const files = report.suites.map((suite) => suite.file);

  for (const n of [2, 3]) {
    it(`gives, for n = ${n}, every file once and whole, in order, and the listing's tests in all`, () => {
      const parts = [];
      for (let k = 1; k <= n; k += 1) parts.push(partOf(report, k, n));
      assert.deepEqual(parts.flatMap(namesOf), files);
      assert.equal(sum(parts.map(testsOf)), parts[0].totalTests);
      assert.equal(parts[0].totalFiles, files.length);

      for (let k = 1; k <= n; k += 1) {
        const cli_ = cli([`${k}/${n}`, real]);
        assert.equal(cli_.status, 0, cli_.stderr);
        const lines = cli_.stdout.trimEnd().split('\n');
        assert.equal(lines[0], `PART ${k}/${n}: ${parts[k - 1].files.length} of ${files.length} spec files, ${testsOf(parts[k - 1])} of ${parts[0].totalTests} tests: ${namesOf(parts[k - 1]).join(' ')}`);
        assert.deepEqual(lines.slice(1), namesOf(parts[k - 1]));
      }
    });
  }
});

// --- the unit's own steps, run without a stack: its listing step on a stub npm, its PART-line parse, its count guard ---

const unitPath = join(here, '..', '..', 'docker', 'tests', 'test-sign-in.sh');
const unitText = readFileSync(unitPath, 'utf8');

/** The lines of the unit's script from the one that matches `from` up to, not including, the one that matches `before`. */
function unitLines(from, before) {
  const lines = unitText.split('\n');
  const start = lines.findIndex((line) => from.test(line));
  assert.ok(start >= 0, `test-sign-in.sh holds a line matching ${from}`);
  const end = lines.findIndex((line, index) => index > start && before.test(line));
  assert.ok(end > start, `test-sign-in.sh holds a line matching ${before} after it`);
  return lines.slice(start, end).join('\n');
}

describe('docker/tests/test-sign-in.sh, its listing step, with a stub npm', () => {
  const stubs = join(work, 'stub-bin');
  const scratch = join(work, 'stub-tmp');
  mkdirSync(stubs, { recursive: true });
  mkdirSync(scratch, { recursive: true });
  writeFileSync(join(stubs, 'npm'), '#!/bin/bash\nprintf \'%s\\n\' "$*" > "$STUB_ARGS"\nif [ -n "${STUB_OUT:-}" ]; then cat "$STUB_OUT"; fi\nexit "${STUB_RC:-0}"\n');
  chmodSync(join(stubs, 'npm'), 0o755);

  function unit(name, args, { out, rc = 0 }) {
    const argsFile = join(work, `${name}.args`);
    const env = { ...bareEnv(), PATH: `${stubs}:${process.env.PATH}`, TMPDIR: scratch, STUB_ARGS: argsFile, STUB_RC: String(rc) };
    if (out !== undefined) env.STUB_OUT = out;
    rmSync(argsFile, { force: true });
    const run = spawnSync('bash', [unitPath, ...args], { env, encoding: 'utf8' });
    return { run, text: run.stdout + run.stderr, argsFile };
  }

  const leftovers = () => readdirSync(scratch).filter((entry) => entry.startsWith('ocutalon-part.'));

  it('lists the project with Playwright, removes its temporary files, and exits 2 for a part the listing refuses', () => {
    const out = listingFile('stub-today.json', listing(TODAY));
    for (const arg of [['--part=19/19'], ['--part', '19/19'], ['--part=3/2']]) {
      const { run, text, argsFile } = unit('refuse', arg, { out });
      assert.equal(run.status, 2, text);
      assert.equal(text.trimEnd().split('\n').length, 1, `one line: ${text}`);
      assert.ok(!/LOCK/.test(text));
      assert.equal(readFileSync(argsFile, 'utf8').trim(), '--silent --prefix web run e2e -- --list --reporter=json');
      assert.deepEqual(leftovers(), [], 'the listing files are removed');
    }
  });

  it('exits 1, before any lock, when the listing cannot be made or holds errors', () => {
    const failing = unit('failing', ['--part', '1/2'], { out: listingFile('stub-text.json', 'Error: a spec failed to load'), rc: 1 });
    assert.equal(failing.run.status, 1, failing.text);
    assert.match(failing.text, /FAIL the chromium project's spec files could not be listed/);
    assert.deepEqual(leftovers(), []);
    const broken = unit('broken', ['--part', '1/2'], { out: listingFile('stub-errors.json', { ...listing([1, 1]), errors: [{ message: 'SyntaxError in a.spec.ts' }] }) });
    assert.equal(broken.run.status, 1, broken.text);
    assert.match(broken.text, /SyntaxError in a\.spec\.ts/);
    for (const { text } of [failing, broken]) assert.ok(!/LOCK/.test(text));
    assert.deepEqual(leftovers(), []);
  });

  it("prints the PART line and names the part in its texts, and with no part prints nothing and keeps the whole unit's texts", () => {
    // The script's part block (from `part_label=""` to the bundle rebuild) runs on its own, after the arguments were read.
    const block = unitLines(/^part_label=""$/, /^LIVE_REBUILD_WEB=1$/);
    const out = listingFile('stub-block.json', listing(TODAY));
    const env = { ...bareEnv(), PATH: `${stubs}:${process.env.PATH}`, TMPDIR: scratch, STUB_ARGS: join(work, 'block.args'), STUB_OUT: out };
    const run = (given, part) => {
      const harness = ['set -u', `script_dir=${JSON.stringify(dirname(unitPath))}`, `part=${JSON.stringify(part)}`, `part_given=${given}`, block, 'printf \'specs=%s\\nsummary=%s\\n\' "$chromium_specs" "$summary"'].join('\n');
      return spawnSync('bash', ['-c', harness], { env, encoding: 'utf8' });
    };
    const part = run(1, '2/2');
    assert.equal(part.status, 0, part.stderr);
    assert.deepEqual(part.stdout.trimEnd().split('\n'), [
      describePart(listing(TODAY), 2, 2).split('\n')[0],
      'specs=of these rows, those in the spec files of part 2/2 of the chromium project',
      'summary=test-sign-in part 2/2',
    ]);
    const whole = run(0, '');
    assert.equal(whole.status, 0, whole.stderr);
    assert.equal(whole.stdout, 'specs=the specs of the chromium project\nsummary=test-sign-in\n');
    assert.deepEqual(leftovers(), []);
  });
});

describe('docker/tests/test-sign-in.sh, its PART-line parse and its count guard', () => {
  it('reads the part and its test count from the line the helper prints', () => {
    const parse = unitLines(/^ {2}part_label=/, /^ {2}case \$part_label\$part_tests in/);
    const line = describePart(listing(TODAY), 2, 2).split('\n')[0];
    const run = spawnSync('bash', ['-c', `set -u\npart_line=$1\n${parse}\nprintf '%s|%s\\n' "$part_label" "$part_tests"`, 'bash', line], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout.trim(), '2/2|96');
  });

  const green = (text) => `\u001b[32m${text}\u001b[39m`;
  const dim = (text) => `\u001b[2m${text}\u001b[22m`;
  const summary = (...parts) => ['Running 20 tests using 1 worker', '  ok 1 a test that 7 passed', '', ...parts, ''].join('\n');

  /** Runs the script's own verdict block (from `part_ran=""` to the failure count) on a browser log, with the helpers stubbed. */
  function verdict({ log, status = 0, label = '1/2', tests = '126' }) {
    const block = unitLines(/^part_ran=""$/, /^if \[ "\$fails" -ne 0 \]/);
    const logPath = join(work, 'e2e.log');
    writeFileSync(logPath, log);
    const harness = [
      'set -u',
      'fails=0',
      'show_log() { :; }',
      'fail() { echo "FAIL $1"; fails=1; }',
      'pass() { echo "PASS $1"; }',
      `e2e_log=${JSON.stringify(logPath)}`,
      `e2e_status=${status}`,
      `part_label=${JSON.stringify(label)}`,
      `part_tests=${JSON.stringify(tests)}`,
      'chromium_specs="the specs"',
      block,
    ].join('\n');
    return spawnSync('bash', ['-c', harness], { encoding: 'utf8' }).stdout.trim();
  }

  it('passes a part whose passed tests are its count, with colour codes and a duration on the line', () => {
    const out = verdict({ log: summary(`  ${green('126 passed')}${dim(' (4.1m)')}`) });
    assert.match(out, /^PASS .*the specs pass \(126 passed\)$/);
  });

  it('counts skipped tests with the passed ones, and ignores a flaky line', () => {
    const out = verdict({ log: summary('  1 flaky', '  26 skipped', `  ${green('100 passed')}${dim(' (4.1m)')}`) });
    assert.match(out, /^PASS /);
  });

  it('fails a part that ran fewer or more tests than it lists, naming both counts, even with exit 0', () => {
    assert.equal(verdict({ log: summary('  19 passed (3s)'), tests: '20', label: '1/18' }), 'FAIL part 1/18 ran 19 of its 20 tests');
    assert.equal(verdict({ log: summary('  21 passed (3s)'), tests: '20', label: '1/18' }), 'FAIL part 1/18 ran 21 of its 20 tests');
    assert.equal(verdict({ log: 'Running 0 tests\n', tests: '20', label: '1/18' }), 'FAIL part 1/18 ran 0 of its 20 tests');
    assert.match(verdict({ log: summary('  17 passed', '  3 skipped'), tests: '20', label: '2/2' }), /^PASS /);
  });

  it('fails a run that exits non-zero, whatever its counts, and leaves a run with no part unguarded', () => {
    assert.match(verdict({ log: summary('  126 passed'), status: 1 }), /^FAIL .*failed \(exit 1\)$/);
    assert.match(verdict({ log: 'no summary at all\n', label: '', tests: '' }), /^PASS /);
  });
});

// --- ci/iris.sh live hands the arguments after the unit name to the unit's script, and nothing else changes ---

describe('ci/iris.sh live, its pass-through', () => {
  const irisPath = join(here, '..', '..', 'ci', 'iris.sh');
  const root = join(work, 'live-root');
  mkdirSync(join(root, 'docker', 'tests'), { recursive: true });
  writeFileSync(join(root, 'docker', 'tests', 'test-fake.sh'), '#!/bin/bash\necho "argc=$#"\nfor a in "$@"; do echo "arg=[$a]"; done\n');

  function live(...args) {
    // The function itself is cut out of ci/iris.sh; the checks around it (lock, docker, Chromium) are stubbed.
    const harness = [
      'set -u',
      'BROWSER_UNITS=""; FIREFOX_WEBKIT_UNITS=""; WARM_MODE=cold',
      'live_known() { [ "$1" = fake ]; }; warm_check() { :; }; setup_tag() { :; }; preflight() { :; }',
      `eval "$(sed -n '/^cmd_live() {/,/^}/p' ${JSON.stringify(irisPath)})"`,
      'cmd_live "$@"',
    ].join('\n');
    return spawnSync('bash', ['-c', harness, 'bash', ...args], { cwd: root, env: bareEnv(), encoding: 'utf8' });
  }

  it('gives the script no argument when there is none after the unit name, as before', () => {
    const run = live('fake');
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, 'PORT the web port of the browser units: auto\nargc=0\n');
  });

  it('gives the script the arguments after the unit name, each whole', () => {
    const run = live('fake', '--part', '1/2', 'two words');
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, 'PORT the web port of the browser units: auto\nargc=3\narg=[--part]\narg=[1/2]\narg=[two words]\n');
  });

  it('still refuses an unknown unit with exit 2', () => {
    const run = live('nope', '--part', '1/2');
    assert.equal(run.status, 2);
    assert.match(run.stdout, /unknown live unit 'nope'/);
  });
});

// --- the hosted web job runs these tests, so a push that changes only the script they read and cut must start the job ---

describe('WEB_INPUT_PATTERN of ci/units.sh, applied the way ci/changes.sh applies it', () => {
  const unitsPath = join(here, '..', '..', 'ci', 'units.sh');

  /** Whether the pattern, read from ci/units.sh and applied with LC_ALL=C grep -Eq, matches `path` as a changed path. */
  function matches(path) {
    const run = spawnSync('bash', ['-c', '. "$1" && printf "%s\\n" "$2" | LC_ALL=C grep -Eq -- "$WEB_INPUT_PATTERN"', 'bash', unitsPath, path], {
      env: bareEnv(),
      encoding: 'utf8',
    });
    assert.ok(run.status === 0 || run.status === 1, `the pattern could not be applied (status ${run.status}): ${run.stderr}`);
    return run.status === 0;
  }

  it('matches docker/tests/test-sign-in.sh, the script that this file reads and runs', () => {
    const fromRoot = relative(join(here, '..', '..'), unitPath);
    assert.equal(matches(fromRoot), true, fromRoot);
  });

  it('does not match a near miss of that path', () => {
    for (const path of ['docker/tests/test-sign-in.sh.bak', 'docker/tests/test-signXin.sh', 'docker/tests/test-sign-inXsh', 'docker/tests/test-sign-in-x.sh', 'docker/tests/sub/test-sign-in.sh', 'old/docker/tests/test-sign-in.sh']) {
      assert.equal(matches(path), false, path);
    }
  });
});
