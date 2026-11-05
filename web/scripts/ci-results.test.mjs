// Pins the Playwright results that CI keeps (Story 11.22, DW-710): each live unit writes them to a folder of its own (ci/iris.sh cmd_live sets
// OCUTALON_E2E_OUTPUT to test-results/<unit>, which web/playwright.config.ts reads as outputDir), so that a later unit of the same job does not
// clear an earlier unit's results, and traces stay off with and without CI (a trace can hold the sign-in passwords of the job's throwaway
// stack, and the repository is public). No browser starts and no stack is needed.
// Run with: node --test web/scripts/
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const webRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = join(webRoot, '..');
const configUrl = pathToFileURL(join(webRoot, 'playwright.config.ts')).href;

/** The outputDir and every trace option that the config holds when it is loaded with the given variables (and none of the OCUTALON_E2E_ ones otherwise). */
function loadConfig(extra) {
  const env = { ...process.env };
  delete env.OCUTALON_E2E_OUTPUT;
  delete env.CI;
  Object.assign(env, extra);
  const script = `const { default: config } = await import(${JSON.stringify(configUrl)});
    console.log(JSON.stringify({ outputDir: config.outputDir, trace: config.use?.trace, projects: (config.projects ?? []).map((project) => project.use?.trace) }));`;
  const run = spawnSync(process.execPath, ['--input-type=module', '-e', script], { cwd: webRoot, env, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr.slice(0, 2000));
  return JSON.parse(run.stdout.trim().split('\n').pop());
}

describe('the Playwright results of a unit (DW-710)', () => {
  it('writes to test-results with no variable, and to the unit folder that OCUTALON_E2E_OUTPUT names', () => {
    assert.equal(loadConfig({}).outputDir, 'test-results');
    assert.equal(loadConfig({ OCUTALON_E2E_OUTPUT: '' }).outputDir, 'test-results');
    assert.equal(loadConfig({ OCUTALON_E2E_OUTPUT: 'test-results/sign-in' }).outputDir, 'test-results/sign-in');
    assert.equal(loadConfig({ OCUTALON_E2E_OUTPUT: 'test-results/cards', CI: '1' }).outputDir, 'test-results/cards');
  });

  it('keeps traces off, with and without CI and with a unit folder', () => {
    for (const extra of [{}, { CI: '1' }, { CI: 'true', OCUTALON_E2E_OUTPUT: 'test-results/online-session' }]) {
      const config = loadConfig(extra);
      assert.equal(config.trace, 'off', JSON.stringify(extra));
      assert.deepEqual(
        config.projects.filter((trace) => trace !== null && trace !== 'off'),
        [],
        `no project turns a trace on (${JSON.stringify(extra)})`,
      );
    }
  });

  it('gives every live unit its own folder: cmd_live of ci/iris.sh sets OCUTALON_E2E_OUTPUT="test-results/$name"', () => {
    const script = readFileSync(join(repoRoot, 'ci', 'iris.sh'), 'utf8');
    const start = script.indexOf('cmd_live() {');
    assert.notEqual(start, -1, 'ci/iris.sh has cmd_live');
    const body = script.slice(start, script.indexOf('\n}\n', start));
    assert.ok(body.includes('OCUTALON_E2E_OUTPUT="test-results/$name" bash "docker/tests/test-$name.sh"'), 'the unit script runs with its own output folder');
  });
});
