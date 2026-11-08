// Pins the Playwright results that CI keeps (Story 11.22, DW-710): each live unit writes them to a folder of its own (ci/iris.sh cmd_live sets
// OCUTALON_E2E_OUTPUT to test-results/<unit>, which web/playwright.config.ts reads as outputDir), so that a later unit of the same job does not
// clear an earlier unit's results. Traces are off in every case but one (Story 11.27): OCUTALON_E2E_TRACE=retain-on-failure together with
// RUNNER_ENVIRONMENT=self-hosted keeps a failing test's trace without screenshots, and ci/iris.sh moves it to the runner's own disk (a trace
// can hold the sign-in passwords of the job's throwaway stack, and the repository is public). It also pins the iris job's one upload in ci.yml: a failure-only upload of web/test-results, kept 3 days.
// No browser starts and no stack is needed.
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
  delete env.OCUTALON_E2E_TRACE;
  delete env.RUNNER_ENVIRONMENT;
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

  it('keeps traces off, with and without CI, with a unit folder, and unless the switch and a self-hosted runner both say otherwise', () => {
    const off = [
      {},
      { CI: '1' },
      { CI: 'true', OCUTALON_E2E_OUTPUT: 'test-results/online-session' },
      { OCUTALON_E2E_TRACE: 'retain-on-failure' },
      { RUNNER_ENVIRONMENT: 'self-hosted' },
      { OCUTALON_E2E_TRACE: 'retain-on-failure', RUNNER_ENVIRONMENT: 'github-hosted' },
      { OCUTALON_E2E_TRACE: 'on', RUNNER_ENVIRONMENT: 'self-hosted' },
    ];
    for (const extra of off) {
      const config = loadConfig(extra);
      assert.equal(config.trace, 'off', JSON.stringify(extra));
      assert.deepEqual(
        config.projects.filter((trace) => trace !== null && trace !== 'off'),
        [],
        `no project turns a trace on (${JSON.stringify(extra)})`,
      );
    }
  });

  it('keeps a failing test\'s trace, without screenshots, on a self-hosted runner that ci/iris.sh set the switch for', () => {
    const config = loadConfig({ OCUTALON_E2E_TRACE: 'retain-on-failure', RUNNER_ENVIRONMENT: 'self-hosted', OCUTALON_E2E_OUTPUT: 'test-results/cards' });
    assert.deepEqual(config.trace, { mode: 'retain-on-failure', screenshots: false });
    assert.equal(config.outputDir, 'test-results/cards');
    assert.deepEqual(
      config.projects.filter((trace) => trace !== null && trace !== undefined),
      [],
      'no project sets a trace of its own: each inherits the ruled object',
    );
  });

  it('gives every live unit its own folder: cmd_live of ci/iris.sh sets OCUTALON_E2E_OUTPUT="test-results/$name"', () => {
    const script = readFileSync(join(repoRoot, 'ci', 'iris.sh'), 'utf8');
    const start = script.indexOf('cmd_live() {');
    assert.notEqual(start, -1, 'ci/iris.sh has cmd_live');
    const body = script.slice(start, script.indexOf('\n}\n', start));
    assert.ok(body.includes('OCUTALON_E2E_OUTPUT="test-results/$name" bash "docker/tests/test-$name.sh"'), 'the unit script runs with its own output folder');
  });
});

describe('the upload of a failed unit (DW-710)', () => {
  const workflow = readFileSync(join(repoRoot, '.github', 'workflows', 'ci.yml'), 'utf8');
  const iris = workflow.slice(workflow.indexOf('\n  iris:\n'));
  /** The text of the step with the given name in the iris job, up to the next step. */
  function stepOf(name) {
    const start = iris.indexOf(`      - name: ${name}\n`);
    assert.notEqual(start, -1, `the iris job has the step "${name}"`);
    const next = iris.indexOf('\n      - name:', start + 1);
    return { start, text: `${iris.slice(start, next === -1 ? undefined : next)}\n` };
  }

  it('the iris job uploads web/test-results of a failure only, kept 3 days, between the group and the teardown', () => {
    const upload = stepOf('Keep the Playwright results');
    assert.ok(upload.text.includes("\n        if: failure() && steps.changes.outputs.run != 'false'\n"), 'only a failure of a job that ran the group');
    assert.match(upload.text, /\n        uses: actions\/upload-artifact@[0-9a-f]{40} # v\d+\.\d+\.\d+\n/, 'pinned by commit');
    assert.match(upload.text, /\n          name: playwright-results-\$\{\{ matrix\.group \}\}-\$\{\{ github\.run_attempt \}\}\n/, 'one artifact per group and attempt');
    assert.ok(upload.text.includes('\n          path: web/test-results/\n'), 'the results folder and nothing else');
    assert.ok(upload.text.includes('\n          retention-days: 3\n'), 'kept 3 days');
    assert.ok(upload.text.includes('\n          if-no-files-found: ignore\n'), 'a unit that wrote nothing is not an error');
    assert.ok(!/\n\s+env:/.test(upload.text) && !/secrets|always\(\)/.test(upload.text), 'no env, no secret, no always()');
    assert.ok(stepOf('Run the group').start < upload.start && upload.start < stepOf('Tear down').start, 'after Run the group, before Tear down');
  });

  it('is the only upload-artifact of the workflow', () => {
    assert.equal(workflow.split('actions/upload-artifact@').length - 1, 1);
  });
});
