// Pins the pure parts of Story 32.6 (DW-550, DW-774), the diagnosis and the one logged retry of a live page's snapshot wait:
// - e2e/support/bounds.ts: diagnosedAtBound, firstAttemptMs, retryLine, retryLocation and reportRetry;
// - e2e/support/host.ts: the worker host's `DIAG ... host:` line from a stand-in reading;
// - ci/iris.sh: cmd_live prints and counts the RETRY lines of its unit, and cmd_group prints the RETRIES line before its GROUP line.
// The modules are imported as they are: Node strips their types, which holds only while they keep to erasable syntax and no relative import.
// Run with: node --test web/scripts/state-wait.test.mjs
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..', '..');
const support = (name) => pathToFileURL(join(here, '..', 'e2e', 'support', name)).href;
const { RETRY_LOG_VARIABLE, RETRY_MIN_ATTEMPT_MS, diagnosedAtBound, firstAttemptMs, reportRetry, retryLine, retryLocation } = await import(support('bounds.ts'));
const { describeHost, parsePressure, readHost, swapInMark } = await import(support('host.ts'));

const work = mkdtempSync(join(tmpdir(), 'state-wait-'));
process.on('exit', () => rmSync(work, { recursive: true, force: true }));

const STEP = 'loadedAfter the snapshot GET /ocutalon/api/v1/state';

describe('diagnosedAtBound', () => {
  it('resolves like the work, without a diagnosis', async () => {
    let diagnosed = 0;
    assert.equal(await diagnosedAtBound(Promise.resolve(7), STEP, async () => void (diagnosed += 1)), 7);
    assert.equal(diagnosed, 0);
  });

  it('does not diagnose another error, and rethrows it unchanged', async () => {
    let diagnosed = 0;
    const failure = new Error(`${STEP}: the snapshot is served`);
    await assert.rejects(
      diagnosedAtBound(Promise.reject(failure), STEP, async () => void (diagnosed += 1)),
      (error) => error === failure,
    );
    const other = new Error('loadedAfter the sign-in: no answer within 30 s');
    await assert.rejects(
      diagnosedAtBound(Promise.reject(other), STEP, async () => void (diagnosed += 1)),
      (error) => error === other,
    );
    assert.equal(diagnosed, 0);
  });

  it('diagnoses a bound message once, before it rethrows the same error', async () => {
    const order = [];
    const failure = new Error(`${STEP}: no answer within 30 s (capped by the test timeout: 40 s left, the own bound is 60 s)`);
    await assert.rejects(
      diagnosedAtBound(Promise.reject(failure), STEP, async () => {
        await new Promise((resolve) => setTimeout(resolve, 20));
        order.push('diagnosed');
      }),
      (error) => {
        order.push('rejected');
        return error === failure;
      },
    );
    assert.deepEqual(order, ['diagnosed', 'rejected']);
  });

  it('still gives the original error when the diagnosis throws or rejects', async () => {
    const failure = new Error(`${STEP}: no answer within 30 s`);
    await assert.rejects(
      diagnosedAtBound(Promise.reject(failure), STEP, () => {
        throw new Error('the diagnosis broke');
      }),
      (error) => error === failure,
    );
    await assert.rejects(
      diagnosedAtBound(Promise.reject(failure), STEP, () => Promise.reject(new Error('the diagnosis failed'))),
      (error) => error === failure,
    );
  });

  it('does not take another step\'s bound message for its own', async () => {
    let diagnosed = 0;
    await assert.rejects(diagnosedAtBound(Promise.reject(new Error('page.close: no answer within 30 s')), STEP, async () => void (diagnosed += 1)));
    assert.equal(diagnosed, 0);
  });
});

describe('the split of the snapshot bound', () => {
  it('gives the first attempt half of a bound of 20 s or more, and none below it or without a finite bound', () => {
    assert.equal(RETRY_MIN_ATTEMPT_MS, 10_000);
    assert.equal(firstAttemptMs(30_000), 15_000);
    assert.equal(firstAttemptMs(20_000), 10_000);
    assert.equal(firstAttemptMs(19_999), undefined);
    assert.equal(firstAttemptMs(5_000), undefined);
    assert.equal(firstAttemptMs(Infinity), undefined);
    assert.equal(firstAttemptMs(Number.NaN), undefined);
    assert.equal(firstAttemptMs(45_001), 22_500);
  });
});

describe('the RETRY line', () => {
  const realLog = console.log;
  const saved = process.env[RETRY_LOG_VARIABLE];
  let lines = [];
  beforeEach(() => {
    lines = [];
    console.log = (...args) => void lines.push(args.join(' '));
  });
  afterEach(() => {
    console.log = realLog;
    if (saved === undefined) delete process.env[RETRY_LOG_VARIABLE];
    else process.env[RETRY_LOG_VARIABLE] = saved;
  });

  it('is `RETRY <location> <step>`', () => {
    assert.equal(retryLine('e2e/cards/incident-card.spec.ts:454', STEP), `RETRY e2e/cards/incident-card.spec.ts:454 ${STEP}`);
  });

  it('names unknown:0 outside a test', () => {
    assert.equal(retryLocation(), 'unknown:0');
  });

  it('is printed, and appended to the file that OCUTALON_E2E_RETRY_LOG names, folder made as needed', () => {
    const file = join(work, 'retries', 'deeper', 'live-retries.txt');
    process.env[RETRY_LOG_VARIABLE] = file;
    reportRetry(STEP);
    reportRetry(STEP);
    assert.deepEqual(lines, [`RETRY unknown:0 ${STEP}`, `RETRY unknown:0 ${STEP}`]);
    assert.equal(readFileSync(file, 'utf8'), `RETRY unknown:0 ${STEP}\nRETRY unknown:0 ${STEP}\n`);
  });

  it('is only printed when the variable is unset or empty', () => {
    delete process.env[RETRY_LOG_VARIABLE];
    reportRetry(STEP);
    process.env[RETRY_LOG_VARIABLE] = '';
    reportRetry(STEP);
    assert.equal(lines.length, 2);
  });

  it('swallows a file that cannot be written, and still prints the line', () => {
    const blocker = join(work, 'a-file');
    writeFileSync(blocker, 'x');
    process.env[RETRY_LOG_VARIABLE] = join(blocker, 'under', 'retries.txt');
    assert.doesNotThrow(() => reportRetry(STEP));
    assert.deepEqual(lines, [`RETRY unknown:0 ${STEP}`]);
  });
});

describe('the host line', () => {
  const PRESSURE = (some, full) => `some avg10=${some} avg60=0.50 avg300=0.10 total=123\n${full === undefined ? '' : `full avg10=${full} avg60=0.00 avg300=0.00 total=45\n`}`;
  const sources = (files, load1 = 3.25, cpus = 4) => ({ read: (path) => files[path], load1: () => load1, cpus: () => cpus });
  const FILES = { '/proc/pressure/cpu': PRESSURE('12.50'), '/proc/pressure/memory': PRESSURE('3.00', '1.25'), '/proc/pressure/io': PRESSURE('40.10', '35.00'), '/proc/vmstat': 'pgfault 1\npswpin 1000\npswpout 5\n' };

  it('parses the avg10 of the some and full lines', () => {
    assert.deepEqual(parsePressure(PRESSURE('12.50', '1.25')), { some: 12.5, full: 1.25 });
    assert.deepEqual(parsePressure(PRESSURE('0.00')), { some: 0 });
    assert.deepEqual(parsePressure('garbage'), {});
  });

  it('reads the pswpin count', () => {
    assert.deepEqual(swapInMark(5000, sources(FILES)), { pages: 1000, at: 5000 });
    assert.equal(swapInMark(5000, sources({})), undefined);
    assert.equal(swapInMark(5000, sources({ '/proc/vmstat': 'pswpin lots\n' })), undefined);
  });

  it('describes the load, the pressure and the swap-in rate of the wait', () => {
    const later = { ...FILES, '/proc/vmstat': 'pswpin 1600\n' };
    const reading = readHost({ pages: 1000, at: 1_000 }, 31_000, sources(later));
    assert.deepEqual(reading.swapIn, { pages: 600, seconds: 30 });
    assert.equal(
      describeHost('DIAG /state host', reading),
      'DIAG /state host: 1-minute load 3.3 on 4 CPU(s), pressure avg10 in percent: cpu some 12.5, full n/a, memory some 3.0, full 1.3, io some 40.1, full 35.0, swap-in 20.0 pages/s over 30.0 s',
    );
  });

  it('says so when the swap-in could not be measured', () => {
    const reading = readHost(undefined, 31_000, sources(FILES));
    assert.match(describeHost('DIAG page.close host', reading), /^DIAG page\.close host: 1-minute load 3\.3 on 4 CPU\(s\), pressure avg10 in percent: .*, swap-in not measured$/);
  });

  it('says not measured where /proc/pressure is missing, and reads nothing from it', () => {
    const reading = readHost({ pages: 1, at: 1 }, 2_000, sources({ '/proc/pressure/cpu': PRESSURE('1.00') }));
    assert.equal(reading.pressure, undefined);
    assert.equal(describeHost('DIAG /state host', reading), 'DIAG /state host: not measured (no /proc/pressure)');
  });

  it('prints n/a for a value that is not a plain number, and never echoes it', () => {
    const line = describeHost('DIAG /state host', {
      load1: Number.NaN,
      cpus: -1,
      pressure: { cpu: { some: Infinity }, memory: { some: -1 }, io: {} },
      swapIn: { pages: 5, seconds: 0 },
    });
    assert.equal(line, 'DIAG /state host: 1-minute load n/a on n/a CPU(s), pressure avg10 in percent: cpu some n/a, full n/a, memory some n/a, full n/a, io some n/a, full n/a, swap-in not measured');
  });

  it('holds no path, PID, address or host name', () => {
    const line = describeHost('DIAG /state host', readHost({ pages: 1000, at: 1_000 }, 31_000, sources(FILES)));
    assert.doesNotMatch(line, /\/proc\/(?!pressure\))|\d+\.\d+\.\d+\.\d+|pid/i);
  });
});

// --- ci/iris.sh: the RETRY lines of a live unit, and the RETRIES line of a group ---

describe('ci/iris.sh counts the retries', () => {
  const irisPath = join(repoRoot, 'ci', 'iris.sh');
  const RETRY_A = `RETRY e2e/live/socket.spec.ts:151 ${STEP}`;
  const RETRY_B = `RETRY e2e/cards/incident-card.spec.ts:454 ${STEP}`;
  let root;
  let seq = 0;

  function bareEnv(extra = {}) {
    const env = { ...process.env, ...extra };
    for (const key of Object.keys(env)) {
      if (key.startsWith('OCUTALON_') || ['GITHUB_ACTIONS', 'RUNNER_ENVIRONMENT', 'GITHUB_STEP_SUMMARY', 'GITHUB_WORKSPACE'].includes(key)) {
        if (!(key in extra)) delete env[key];
      }
    }
    return env;
  }

  beforeEach(() => {
    seq += 1;
    root = join(work, `iris-${seq}`);
    mkdirSync(join(root, 'docker', 'tests'), { recursive: true });
    mkdirSync(join(root, 'ci'), { recursive: true });
  });

  /** A unit script that writes the given text to the retry file named by the variable, prints a line and exits with rc. */
  function unit(name, { text = '', rc = 0 } = {}) {
    writeFileSync(join(root, 'docker', 'tests', `test-${name}.sh`), `#!/bin/bash\necho "unit ${name} ran"\nmkdir -p "$(dirname "$OCUTALON_E2E_RETRY_LOG")"\nprintf '%b' ${JSON.stringify(text)} >> "$OCUTALON_E2E_RETRY_LOG"\nexit ${rc}\n`);
  }

  function live(name, extra = {}) {
    const harness = [
      'set -u',
      'BROWSER_UNITS=""; FIREFOX_WEBKIT_UNITS=""; WARM_MODE=cold',
      'live_known() { true; }; warm_check() { :; }; setup_tag() { :; }; preflight() { :; }; root=$PWD',
      `eval "$(sed -n '/^TRACE_FOLDER_NAME=/,/^cmd_live() {/p' ${JSON.stringify(irisPath)} | sed '$d')"`,
      `eval "$(sed -n '/^cmd_live() {/,/^}/p' ${JSON.stringify(irisPath)})"`,
      'cmd_live "$@"',
    ].join('\n');
    return spawnSync('bash', ['-c', harness, 'bash', name], { cwd: root, env: bareEnv(extra), encoding: 'utf8' });
  }

  /** cmd_group over the units, whose retries a fake ci/iris.sh writes; the real cmd_live is covered above. */
  function group(units, retries, extra = {}) {
    writeFileSync(
      join(root, 'ci', 'iris.sh'),
      `#!/bin/bash\nmkdir -p web/test-results\ncase $2 in\n${Object.entries(retries)
        .map(([name, text]) => `${name}) printf '%b' ${JSON.stringify(text)} > web/test-results/${name}-retries.txt;;`)
        .join('\n')}\nesac\nexit 0\n`,
    );
    const harness = [
      'set -u',
      `IRIS_GROUPS="g"; group_units() { echo ${JSON.stringify(units)}; }; fresh_only() { :; }; setup_tag() { :; }; preflight() { :; }; ensure_web_bundle() { :; }; root=$PWD`,
      `eval "$(sed -n '/^TRACE_FOLDER_NAME=/,/^cmd_live() {/p' ${JSON.stringify(irisPath)} | sed '$d')"`,
      `eval "$(sed -n '/^cmd_group() {/,/^}/p' ${JSON.stringify(irisPath)})"`,
      'cmd_group g',
    ].join('\n');
    return spawnSync('bash', ['-c', harness], { cwd: root, env: bareEnv(extra), encoding: 'utf8' });
  }

  it('cmd_live prints the unit\'s RETRY lines after its output, then the count, and keeps the unit\'s exit code', () => {
    unit('fake', { text: `${RETRY_A}\nnot a retry line\nRETRY has a /host/path:1 x\n${RETRY_B}\n`, rc: 3 });
    const run = live('fake');
    assert.equal(run.status, 3, run.stderr);
    assert.equal(run.stdout, `PORT the web port of the browser units: auto\nTRACE off: not a CI run\nunit fake ran\n${RETRY_A}\n${RETRY_B}\nRETRIES 2 in live:fake\n`);
  });

  it('cmd_live points the unit at web/test-results/<unit>-retries.txt', () => {
    unit('fake', { text: `${RETRY_A}\n` });
    const run = live('fake');
    assert.equal(run.status, 0, run.stderr);
    assert.equal(readFileSync(join(root, 'web', 'test-results', 'fake-retries.txt'), 'utf8'), `${RETRY_A}\n`);
  });

  it('cmd_live prints nothing new when no test retried, and removes a stale file first', () => {
    mkdirSync(join(root, 'web', 'test-results'), { recursive: true });
    writeFileSync(join(root, 'web', 'test-results', 'fake-retries.txt'), `${RETRY_A}\n`);
    unit('fake');
    const run = live('fake');
    assert.equal(run.status, 0, run.stderr);
    assert.equal(run.stdout, 'PORT the web port of the browser units: auto\nTRACE off: not a CI run\nunit fake ran\n');
    assert.equal(readFileSync(join(root, 'web', 'test-results', 'fake-retries.txt'), 'utf8'), '');
  });

  it('cmd_live prints nothing new when the unit wrote no file', () => {
    writeFileSync(join(root, 'docker', 'tests', 'test-fake.sh'), '#!/bin/bash\necho "unit fake ran"\n');
    const run = live('fake');
    assert.equal(run.stdout, 'PORT the web port of the browser units: auto\nTRACE off: not a CI run\nunit fake ran\n');
    assert.equal(existsSync(join(root, 'web', 'test-results', 'fake-retries.txt')), false);
  });

  it('cmd_group prints the total and the units with retries just before the GROUP line', () => {
    const run = group('live:a live:b', { a: `${RETRY_A}\n` });
    assert.equal(run.status, 0, run.stderr);
    const lines = run.stdout.trimEnd().split('\n');
    assert.equal(lines.at(-2), 'RETRIES 1 in group g (live:a 1)');
    assert.match(lines.at(-1), /^GROUP g passed \(\d+s\)$/);
  });

  it('cmd_group prints RETRIES 0 when no unit retried', () => {
    const run = group('live:a live:b', {});
    const lines = run.stdout.trimEnd().split('\n');
    assert.equal(lines.at(-2), 'RETRIES 0 in group g');
    assert.match(lines.at(-1), /^GROUP g passed /);
  });

  it('cmd_group adds up several units', () => {
    const run = group('live:a live:b', { a: `${RETRY_A}\n`, b: `${RETRY_A}\n${RETRY_B}\n` });
    assert.match(run.stdout, /\nRETRIES 3 in group g \(live:a 1, live:b 2\)\nGROUP g passed/);
  });

  it('cmd_group writes the step summary only above 0, with each RETRY line and its unit', () => {
    const summary = join(work, `summary-${seq}.md`);
    const run = group('live:a live:b', { a: `${RETRY_A}\n`, b: `${RETRY_B}\n` }, { GITHUB_STEP_SUMMARY: summary });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(readFileSync(summary, 'utf8'), `RETRIES 2 in group g (live:a 1, live:b 1)\n- live:a: ${RETRY_A}\n- live:b: ${RETRY_B}\n`);
  });

  it('cmd_group writes no step summary when nothing retried', () => {
    const none = join(work, `summary-none-${seq}.md`);
    const run = group('live:a', {}, { GITHUB_STEP_SUMMARY: none });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(existsSync(none), false);
  });

  it('cmd_group ignores a step summary that cannot be written', () => {
    const run = group('live:a', { a: `${RETRY_A}\n` }, { GITHUB_STEP_SUMMARY: join(work, 'no-such-folder', 'summary.md') });
    assert.equal(run.status, 0, run.stderr);
    assert.match(run.stdout, /RETRIES 1 in group g \(live:a 1\)\nGROUP g passed/);
    assert.doesNotMatch(run.stderr, /no-such-folder/, 'the redirect error is not shown');
  });

  it('names no host path', () => {
    const run = group('live:a', { a: `${RETRY_A}\n` });
    assert.equal(run.stdout.includes(root), false);
    assert.equal(run.stdout.includes(work), false);
  });
});
