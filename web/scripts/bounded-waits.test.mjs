// Pins the bounds of the online units' waits (Story 11.21, e2e/support/bounds.ts): a command that never answers is killed and rejects naming
// its step, the bounds sit in the range that keeps a hang well under the test timeouts, and the config, irisScript and the Telegram fixture
// use them. The module is imported as it is: Node strips its types, which holds only while it keeps to erasable syntax.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = join(here, '..');
const { default: playwrightConfig } = await import(pathToFileURL(join(webRoot, 'playwright.config.ts')).href);
const { ONLINE_IRIS_SCRIPT_MS, ONLINE_WAITS, TELEGRAM_FIXTURE_MS, runBounded, scriptBound } = await import(
  pathToFileURL(join(webRoot, 'e2e', 'support', 'bounds.ts')).href
);

const read = (path) => readFileSync(join(webRoot, path), 'utf8');

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
    assert.match(telegram, /import \{ TELEGRAM_FIXTURE_MS \} from '\.\.\/e2e\/support\/bounds';/);
  });
});
