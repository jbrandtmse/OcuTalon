// Pins the bounds of the online units' waits (Story 11.21, e2e/support/bounds.ts): a command that never answers is killed and rejects naming
// its step, the bounds sit in the range that keeps a hang well under the test timeouts, and the config, irisScript and the Telegram fixture
// use them. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = join(here, '..');
const { default: playwrightConfig } = await import(pathToFileURL(join(webRoot, 'playwright.config.ts')).href);
const {
  CLEANUP_MARGIN_MS,
  CLEANUP_RESERVE_MS,
  DEADLINE_FLOOR_MS,
  DEADLINE_MARGIN_MS,
  ONLINE_IRIS_SCRIPT_MS,
  ONLINE_WAITS,
  SLOW_STEP_MS,
  TELEGRAM_FIXTURE_MS,
  WAIT_CAPS,
  asCleanup,
  boundedStep,
  capToDeadline,
  cleanupReserve,
  effectiveWaits,
  inCleanup,
  runBounded,
  scriptBound,
  secs,
  slowLine,
  testTimeLeftMs,
  waitsFor,
} = await import(
  pathToFileURL(join(webRoot, 'e2e', 'support', 'bounds.ts')).href
);

const read = (path) => readFileSync(join(webRoot, path), 'utf8');
const realSetTimeout = setTimeout;

describe('runBounded', () => {
  it('kills a command that does not answer and rejects naming the step and the bound', { timeout: 5000 }, async () => {
    const started = Date.now();
    await assert.rejects(
      runBounded('sh', ['-c', 'exec sleep 30'], '', 500, 'step X'),
      (error) => error instanceof Error && error.message.includes('step X') && error.message.includes('0.5 s') && error.message.includes('no answer'),
    );
    assert.ok(Date.now() - started < 2000, 'it rejected at its bound, not when the command ended');
  });

  it('kills the command itself, not only the wait for it', { timeout: 5000 }, async () => {
    const dir = mkdtempSync(join(tmpdir(), 'ocutalon-bound-'));
    try {
      const pidFile = join(dir, 'pid');
      await assert.rejects(runBounded('sh', ['-c', `echo $$ > '${pidFile}'; exec sleep 30`], '', 500, 'step X'), /no answer/);
      const pid = Number(readFileSync(pidFile, 'utf8'));
      assert.ok(pid > 0, 'the command wrote its pid');
      let alive = true;
      for (let tries = 0; tries < 40 && alive; tries += 1) {
        try {
          process.kill(pid, 0);
          await new Promise((done) => setTimeout(done, 50));
        } catch {
          alive = false;
        }
      }
      assert.equal(alive, false, 'the command ended with the rejection');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('adds the detail to the message of a rejection', { timeout: 5000 }, async () => {
    await assert.rejects(runBounded('sh', ['-c', 'exec sleep 30'], '', 200, 'step Y', ' from the script starting "Z"'), /^Error: step Y: no answer within 0\.2 s from the script starting "Z"$/);
  });

  it('resolves with the output of a command that prints and exits', async () => {
    assert.equal(await runBounded('sh', ['-c', 'echo hello'], '', 5000, 'step'), 'hello\n');
  });

  it('passes the input to the command and waits without a bound when ms is undefined', async () => {
    assert.equal(await runBounded('cat', [], 'from stdin', undefined, 'step'), 'from stdin');
  });

  it('rejects when the command cannot start', async () => {
    await assert.rejects(runBounded('ocutalon-no-such-command', [], '', 5000, 'step'), /ENOENT/);
  });
});

describe('scriptBound', () => {
  it('reads irisScriptMs from the metadata of a project', () => {
    assert.equal(scriptBound({ irisScriptMs: 90_000 }), 90_000);
  });

  it('is undefined when the metadata sets none or a value that is not positive', () => {
    for (const metadata of [undefined, null, {}, { irisScriptMs: 0 }, { irisScriptMs: -5 }, { irisScriptMs: '90' }, { irisScriptMs: Number.NaN }, { irisScriptMs: Infinity }]) {
      assert.equal(scriptBound(metadata), undefined, JSON.stringify(metadata));
    }
  });
});

describe('boundedStep', () => {
  it('rejects at its bound, naming the step and the bound, and drops the late outcome', { timeout: 5000 }, async () => {
    const started = Date.now();
    await assert.rejects(boundedStep(new Promise(() => undefined), 300, 'step Z'), /^Error: step Z: no answer within 0\.3 s$/);
    assert.ok(Date.now() - started < 2000);
  });

  it('settles like the work when it ends in time, with its value or its error', async () => {
    assert.equal(await boundedStep(Promise.resolve(7), 5000, 'step'), 7);
    const failure = new Error('the work failed');
    await assert.rejects(boundedStep(Promise.reject(failure), 5000, 'step'), (error) => error === failure);
  });
});

describe('waitsFor', () => {
  it('gives a test a share of its timeout, capped, so that a wait fails before the test does', () => {
    assert.deepEqual(waitsFor(45_000), { actionTimeout: 30_000, navigationTimeout: 30_000 });
    assert.deepEqual(waitsFor(90_000), { actionTimeout: 60_000, navigationTimeout: 60_000 });
    assert.deepEqual(waitsFor(240_000), { actionTimeout: WAIT_CAPS.actionTimeout, navigationTimeout: WAIT_CAPS.navigationTimeout });
    for (const testMs of [1_000, 9_000, 45_000, 120_000, 300_000]) {
      const waits = waitsFor(testMs);
      assert.ok(waits.actionTimeout < testMs && waits.navigationTimeout < testMs, `${testMs} ms`);
    }
  });

  it('gives a test with no timeout the caps', () => {
    for (const testMs of [0, -1, Number.NaN, Infinity]) assert.deepEqual(waitsFor(testMs), WAIT_CAPS, String(testMs));
  });
});

describe('effectiveWaits', () => {
  it('keeps the waits that the project sets (the online projects) and derives the rest from the test timeout', () => {
    assert.deepEqual(effectiveWaits(120_000, ONLINE_WAITS), { action: ONLINE_WAITS.actionTimeout, navigation: ONLINE_WAITS.navigationTimeout });
    assert.deepEqual(effectiveWaits(45_000, { actionTimeout: 4_000 }), { action: 4_000, navigation: 30_000 });
    assert.deepEqual(effectiveWaits(45_000, {}), { action: 30_000, navigation: 30_000 });
    assert.deepEqual(effectiveWaits(240_000, { actionTimeout: 0, navigationTimeout: 0 }), { action: WAIT_CAPS.actionTimeout, navigation: WAIT_CAPS.navigationTimeout });
    assert.deepEqual(effectiveWaits(45_000, undefined), { action: 30_000, navigation: 30_000 });
  });
});

describe('the bounds', () => {
  it('keep a hang well under the 120 to 300 s test timeouts and above the waits they must not cut', () => {
    for (const ms of [ONLINE_IRIS_SCRIPT_MS, ONLINE_WAITS.actionTimeout, ONLINE_WAITS.navigationTimeout]) {
      assert.ok(ms >= 10_000 && ms <= 120_000, `${ms} ms`);
    }
    assert.ok(TELEGRAM_FIXTURE_MS > 140_000 && TELEGRAM_FIXTURE_MS <= 150_000, `${TELEGRAM_FIXTURE_MS} ms is above the fixture's 140 s chain`);
  });
});

describe('by source', () => {
  const config = read('playwright.config.ts');

  it('gives each online project the waits and the script bound, and no other project', () => {
    const online = [];
    for (const project of playwrightConfig.projects) {
      const isOnline = String(project.testDir).startsWith('./e2e-online');
      if (isOnline) online.push(project.name);
      assert.equal(project.use?.actionTimeout, isOnline ? ONLINE_WAITS.actionTimeout : undefined, `${project.name}: use.actionTimeout`);
      assert.equal(project.use?.navigationTimeout, isOnline ? ONLINE_WAITS.navigationTimeout : undefined, `${project.name}: use.navigationTimeout`);
      assert.equal(project.metadata?.irisScriptMs, isOnline ? ONLINE_IRIS_SCRIPT_MS : undefined, `${project.name}: metadata.irisScriptMs`);
    }
    assert.deepEqual(online.sort(), ['online-allowance', 'online-demo', 'online-demo-path', 'online-session', 'online-visitors']);
  });

  it('takes both numbers from bounds.ts', () => {
    assert.match(config, /import \{ ONLINE_IRIS_SCRIPT_MS, ONLINE_WAITS \} from '\.\/e2e\/support\/bounds\.ts';/);
  });

  it('irisScript takes its bound from the metadata of the running project', () => {
    const iris = read('e2e/support/iris.ts');
    assert.match(iris, /scriptBound\(test\.info\(\)\.project\.metadata\)/);
    assert.match(iris, /export async function irisScript\(script: string, ms: number \| undefined = currentBound\(\)\)/);
    assert.match(iris, /runOnce\(script, ms\)/);
  });

  it('the Telegram fixture call passes TELEGRAM_FIXTURE_MS', () => {
    const telegram = read('e2e-online/telegram.ts');
    const body = telegram.slice(telegram.indexOf('async function fixture('), telegram.indexOf('export async function startTelegram'));
    assert.match(body, /\n\s*TELEGRAM_FIXTURE_MS,\n\s*\);/);
    assert.match(telegram, /import \{ TELEGRAM_FIXTURE_MS, asCleanup \} from '\.\.\/e2e\/support\/bounds';/);
  });

  it('the Telegram fixture script starts with a line that names the method, which a stopped call quotes', () => {
    const telegram = read('e2e-online/telegram.ts');
    const body = telegram.slice(telegram.indexOf('async function fixture('), telegram.indexOf('export async function startTelegram'));
    assert.match(body, /\[\n\s*`Set call="TelegramPageFixture\.\$\{call\.slice\(0, call\.indexOf\('\('\)\)\}"`,\n/);
  });

  it('the clean-up helpers that the specs call in finally run as clean-ups', () => {
    const files = { 'e2e-online/telegram.ts': ['finishTelegram', 'unpairChat'], 'e2e-online/support.ts': ['signOutGroup', 'removeSession', 'removeCounterRows', 'cleanPopulated'] };
    for (const [file, names] of Object.entries(files)) {
      const source = read(file);
      for (const name of names) {
        const from = source.indexOf(`export async function ${name}(`);
        assert.ok(from >= 0, `${file}: ${name}`);
        const body = source.slice(from, source.indexOf('\n}\n', from));
        assert.match(body, /await asCleanup\(/, `${file}: ${name} runs through asCleanup`);
      }
    }
  });

  it('the shared test gives the page its waits and keeps them current when the test sets a new timeout', () => {
    const fixtures = read('e2e/support/fixtures.ts');
    assert.match(fixtures, /waitsFor\(testInfo\.timeout\)/);
    assert.match(fixtures, /if \(!actionTimeout\) context\.setDefaultTimeout\(/);
    assert.match(fixtures, /if \(!navigationTimeout\) context\.setDefaultNavigationTimeout\(/);
    assert.match(fixtures, /testInfo\.setTimeout = /);
  });

  it('loadedAfter bounds the sign-in and the snapshot GET, each by name', () => {
    const floor = read('e2e/support/floor.ts');
    assert.match(floor, /boundedStep\(signInAction\(\), waits\.navigation, 'loadedAfter the sign-in'\)/);
    assert.match(floor, /boundedStep\(state, waits\.action, `loadedAfter the snapshot GET \$\{STATE\}`\)/);
  });

  it('the online sign-in helpers bound their waits by name', () => {
    const support = read('e2e-online/support.ts');
    assert.match(support, /boundedStep\(answered, wait, 'signInFromSplash the answer to the sign-in POST'\)/);
    assert.match(support, /boundedStep\(asked, wait, `epochOf the GET \$\{STATE\}`\)/);
  });

  it('gotoSettled passes the navigation wait in force to goto and names the url when it ends', () => {
    const navigate = read('e2e/support/navigate.ts');
    assert.match(navigate, /currentWaits\(\)\?\.navigation/);
    assert.match(navigate, /effectiveWaits\(info\.timeout, info\.project\.use\)/);
    assert.match(navigate, /gotoSettled: no answer within \$\{secs\(bound\.ms\)\} s from \$\{url\}\$\{bound\.note\}/);
    assert.match(navigate, /capToDeadline\(own\)/);
  });
});

describe('the deadline cap', () => {
  it('shortens a bound to the time left before the test timeout minus the margin, never below the floor, and says so', () => {
    assert.deepEqual(capToDeadline(90_000, undefined), { ms: 90_000, note: '' });
    assert.deepEqual(capToDeadline(30_000, 100_000), { ms: 30_000, note: '' });
    const capped = capToDeadline(90_000, 40_000);
    assert.equal(capped.ms, 40_000 - DEADLINE_MARGIN_MS);
    assert.match(capped.note, /capped by the test timeout: 40 s left, the own bound is 90 s/);
    assert.equal(capToDeadline(90_000, 12_000).ms, DEADLINE_FLOOR_MS, 'the floor holds when the margin would leave nothing');
    assert.equal(capToDeadline(90_000, 3000).ms, 2000, 'and never exceeds the time left less a second');
    assert.equal(capToDeadline(90_000, -3000).ms, 1000);
    assert.equal(capToDeadline(2000, 12_000).ms, 2000, 'a bound below the floor is never lengthened');
  });

  it('keeps the clean-up reserve of the test timeout for the clean-ups: a quarter, at least the margin, at most 60 s', () => {
    assert.equal(cleanupReserve(undefined), DEADLINE_MARGIN_MS);
    assert.equal(cleanupReserve(12_000), DEADLINE_MARGIN_MS, 'a short test keeps the margin');
    assert.equal(cleanupReserve(45_000), 11_250, 'the web/e2e default of 45 s keeps a quarter');
    assert.equal(cleanupReserve(120_000), 30_000);
    assert.equal(cleanupReserve(300_000), CLEANUP_RESERVE_MS, 'a long test keeps 60 s');
    assert.equal(capToDeadline(90_000, 100_000, 300_000).ms, 40_000, 'a main step of a 300 s test stops 60 s before it');
    assert.equal(capToDeadline(90_000, 100_000, 120_000).ms, 70_000, 'and of a 120 s test 30 s before it');
    assert.equal(capToDeadline(90_000, 30_000, 45_000).ms, 18_750, 'and of a 45 s test 11.25 s before it');
    assert.equal(capToDeadline(90_000, 50_000, 300_000).ms, DEADLINE_FLOOR_MS, 'within the reserve a main step gets the floor');
  });

  it('gives a clean-up the time left less a small margin, never only the floor', () => {
    const cleanup = capToDeadline(150_000, 60_000, 300_000, true);
    assert.equal(cleanup.ms, 60_000 - CLEANUP_MARGIN_MS);
    assert.match(cleanup.note, /capped by the test timeout: 60 s left for a clean-up, the own bound is 150 s\)$/);
    assert.equal(capToDeadline(150_000, 1500, 300_000, true).ms, 1000);
    assert.deepEqual(capToDeadline(5000, 60_000, 300_000, true), { ms: 5000, note: '' }, 'a clean-up keeps a shorter bound of its own');
  });

  it('caps a wait with no bound of its own inside a test, and leaves it unbounded outside one', () => {
    const capped = capToDeadline(Infinity, 100_000, 300_000);
    assert.equal(capped.ms, 40_000);
    assert.match(capped.note, /100 s left, no own bound\)$/);
    assert.equal(capToDeadline(Infinity, undefined).ms, Infinity);
  });

  it('marks a clean-up through every await of its work, and nothing outside it', async () => {
    assert.equal(inCleanup(), false);
    const seen = await asCleanup(async () => {
      await new Promise((done) => setTimeout(done, 1));
      return inCleanup();
    });
    assert.equal(seen, true);
    assert.equal(inCleanup(), false);
  });

  it('writes a bound in whole seconds or one decimal', () => {
    assert.equal(secs(5000), '5');
    assert.equal(secs(11_250), '11.3');
    assert.equal(secs(500), '0.5');
  });

  it('has no time left to count outside a running test', () => {
    assert.equal(testTimeLeftMs(), undefined);
  });

  it('is applied by boundedStep and runBounded, and marked by the shared test', () => {
    const bounds = read('e2e/support/bounds.ts');
    assert.match(bounds, /const \{ ms: bound, note \} = capToDeadline\(ms\);/);
    assert.match(bounds, /const capped = capToDeadline\(ms \?\? Infinity\);/);
    assert.match(read('e2e/support/fixtures.ts'), /markTestStart\(testInfo\);/);
  });
});

describe('the slow-step breadcrumb', () => {
  it('names the step and the whole seconds of a step that took SLOW_STEP_MS or more, and nothing for a faster one', () => {
    assert.equal(slowLine('irisScript from the script starting "Set r=1"', 37_400), 'SLOW irisScript from the script starting "Set r=1" 37 s');
    assert.equal(slowLine('step', SLOW_STEP_MS), 'SLOW step 10 s');
    assert.equal(slowLine('step', SLOW_STEP_MS - 1), undefined);
  });

  it('is printed by boundedStep, runBounded and gotoSettled', () => {
    const bounds = read('e2e/support/bounds.ts');
    assert.match(bounds, /if \(!over\) reportSlow\(step, startedAt\);/);
    assert.match(bounds, /if \(!timedOut\) reportSlow\(`\$\{step\}\$\{detail\}`, startedAt\);/);
    assert.match(read('e2e/support/navigate.ts'), /reportSlow\(`gotoSettled \$\{url\}`, startedAt\)/);
  });
});

describe('the close of a page', () => {
  it('goes through boundedClose for every page of the context', () => {
    const fixtures = read('e2e/support/fixtures.ts');
    assert.match(
      fixtures,
      /page\.close = \(options\) => diagnosedAtBound\(boundedStep\(close\(options\), waitMs\(\), 'page\.close'\), 'page\.close', \(\) => closeDiagnosis\(page, watch\)\);/,
    );
    assert.match(fixtures, /context\.on\('page', \(page\) => boundedClose\(page, closeWait\)\);/);
  });
});

describe('the slow-step breadcrumb in use', () => {
  const realLog = console.log;
  const realNow = Date.now;
  let lines = [];
  afterEach(() => {
    console.log = realLog;
    Date.now = realNow;
  });
  /** Every Date.now() call moves a fake clock on by 11 s, so a step reads as 11 s long. */
  const slowClock = () => {
    let clock = 0;
    lines = [];
    console.log = (...args) => lines.push(args.join(' '));
    Date.now = () => (clock += 11_000);
  };

  it('boundedStep prints it for a step that settled, in value or in error, and not for one that already timed out', async () => {
    slowClock();
    await boundedStep(Promise.resolve(1), 5000, 'step A');
    await assert.rejects(boundedStep(Promise.reject(new Error('no')), 5000, 'step B'), /no/);
    assert.deepEqual(lines, ['SLOW step A 11 s', 'SLOW step B 11 s']);
    slowClock();
    let late;
    const work = new Promise((resolve) => (late = resolve));
    await assert.rejects(boundedStep(work, 100, 'step C'), /step C: no answer within 0\.1 s/);
    late(1);
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(lines, [], 'a step that timed out is named by its error alone');
  });

  it('runBounded prints it with the step and the detail for a command that closed, and not for one it killed', async () => {
    slowClock();
    await runBounded('sh', ['-c', 'cat > /dev/null'], 'x', undefined, 'irisScript', ' from the script starting "Set a=1"');
    assert.deepEqual(lines, ['SLOW irisScript from the script starting "Set a=1" 11 s']);
    slowClock();
    const dir = mkdtempSync(join(tmpdir(), 'ocutalon-slow-'));
    try {
      const pidFile = join(dir, 'pid');
      await assert.rejects(runBounded('sh', ['-c', `echo $$ > '${pidFile}'; exec sleep 30`], '', 200, 'step K'), /step K: no answer within 0\.2 s/);
      const pid = Number(readFileSync(pidFile, 'utf8'));
      for (let tries = 0; tries < 100; tries += 1) {
        try {
          process.kill(pid, 0);
        } catch {
          break;
        }
        await new Promise((resolve) => realSetTimeout(resolve, 20));
      }
      await new Promise((resolve) => realSetTimeout(resolve, 50));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
    assert.deepEqual(lines, [], 'the killed command has closed, and printed no SLOW line');
  });
});
