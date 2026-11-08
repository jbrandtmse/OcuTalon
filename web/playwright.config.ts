import { defineConfig, devices } from '@playwright/test';

import { ONLINE_IRIS_SCRIPT_MS, ONLINE_WAITS } from './e2e/support/bounds.ts';

/**
 * Browser specs against a running stack. OCUTALON_URL is its origin, for example http://127.0.0.1:52800; the specs
 * open paths below it, such as /ocutalon/. One worker: the specs share one IRIS instance and its licence.
 *
 * Fifteen projects:
 *   chromium       every spec under e2e/ except e2e/demo-path/, e2e/demo-switch/, e2e/floor/, e2e/answers/, e2e/cards/, the folders of sign-in-2 and the
 *                  folders and file of sign-in-3 (the sign-in unit, docker/tests/test-sign-in.sh: the sign-in, API and page specs), Desktop Chrome;
 *   sign-in-2      the specs of the folders of SIGN_IN_2_DIRS (the sign-in-2 unit, docker/tests/test-sign-in-2.sh, which runs test-sign-in.sh's setup on
 *                  this project), Desktop Chrome. The two projects are the spec files that the sign-in unit ran alone until the Contest Planner's
 *                  ruling of 2026-11-05 split it by spec file (it took 1047 s in CI): each file is in exactly one of them;
 *   sign-in-3      the specs of the folders of SIGN_IN_3_DIRS and the files of SIGN_IN_3_FILES (the sign-in-3 unit, docker/tests/test-sign-in-3.sh, which runs
 *                  test-sign-in.sh's setup on this project), Desktop Chrome. The Contest Planner's ruling of 2026-11-07 split the sign-in unit again
 *                  by spec file, because Story 4.11's more-to-try tests had grown it to 1034 s and 1170 s in CI: each file is in exactly one of
 *                  chromium, sign-in-2 and sign-in-3;
 *   demo-path      the step specs of e2e/demo-path/ (the demo-path unit, docker/tests/test-demo-path.sh), Desktop Chrome;
 *   demo-switch    the badge, guide, phone and mailbox specs of e2e/demo-switch/ (the demo-switch unit, docker/tests/test-demo-switch.sh, which names the stack's
 *                  demo mode in OCUTALON_E2E_DEMO_MODE), Desktop Chrome;
 *   floor          the accessibility floor's specs of e2e/floor/ (the floor unit, docker/tests/test-floor.sh), Desktop Chrome: every case;
 *   answers        the specs of e2e/answers/ (the answers unit, docker/tests/test-answers.sh): answering a request on the simulated phone and every copy of
 *                  an answer, Story 6.3's X1 to X10, and every ending of an incident, Story 6.4's C1 to C10, Desktop Chrome;
 *   cards          the specs of e2e/cards/ (the cards unit, docker/tests/test-cards.sh): the incident card and the approval request card, Story 6.1's
 *                  I2 to I11 and Story 6.2's A2 to A10 (I1 and A1 stay in the floor, which runs them in three engines), Desktop Chrome;
 *   floor-firefox  the floor cases tagged @browsers, in Desktop Firefox;
 *   floor-webkit   the floor cases tagged @browsers, in Desktop Safari (WebKit);
 *   online-demo    the specs of e2e-online/ outside e2e-online/session/, e2e-online/allowance/, e2e-online/demo-path/ and e2e-online/visitors/ (the online-demo unit,
 *                  docker/tests/test-online-demo.sh), Desktop Chrome;
 *   online-session the specs of e2e-online/session/ (the online-session unit, docker/tests/test-online-session.sh): leaving the page and
 *                  Sign out on a flag-on stack, Story 16.4, Desktop Chrome;
 *   online-allowance the specs of e2e-online/allowance/ (the online-allowance unit, docker/tests/test-online-allowance.sh): the message
 *                  allowance, the daily cap and the simulated-email limit on a flag-on stack of its own, Story 16.9, Desktop Chrome;
 *   online-demo-path the specs of e2e-online/demo-path/ (the online-demo-path unit, docker/tests/test-online-demo-path.sh): REL-2's online run and
 *                  the second visitor, with the model keys at the CI mock, Story 29.4, Desktop Chrome;
 *   online-visitors the specs of e2e-online/visitors/ (the online-visitors unit, docker/tests/test-online-visitors.sh), Story 29.7, Desktop Chrome.
 * The floor unit runs the three floor projects one after the other on its one stack (the e2e:floor script), Chromium first.
 * The five online projects bound their waits (e2e/support/bounds.ts): a page action, a navigation and an irisScript session each fail on their own bound.
 * When OCUTALON_E2E_JSON names a file, a JSON report is written there beside the list reporter.
 * Traces are off unless ci/iris.sh sets OCUTALON_E2E_TRACE=retain-on-failure on a self-hosted runner (RUNNER_ENVIRONMENT=self-hosted, checked
 * here too): then a failing test keeps its trace without screenshots, and ci/iris.sh moves it off the workspace (Story 11.27, DW-550, DW-774).
 */
const jsonReport = process.env['OCUTALON_E2E_JSON'];
const keepTraces = process.env['OCUTALON_E2E_TRACE'] === 'retain-on-failure' && process.env['RUNNER_ENVIRONMENT'] === 'self-hosted';

/**
 * The folders of e2e/ whose specs the sign-in-2 project runs and the chromium project does not: a contiguous run of the chromium project's
 * folders in path order, so that each unit runs its files in the order the one unit ran them. A spec file added to one of these folders joins
 * sign-in-2, and one added anywhere else under e2e/ outside the folders of the other projects joins chromium.
 */
const SIGN_IN_2_DIRS = ['live', 'phone', 'rail', 'reminder', 'session', 'settings'];

/**
 * The folders and the root file of e2e/ whose specs the sign-in-3 project runs and the chromium project does not: a contiguous run of the
 * chromium project's files in path order (guide/*, heartbeat/heartbeat.spec.ts and heartbeat-card.spec.ts), so that each unit runs its files in
 * the order the one unit ran them. A spec file added to one of these folders joins sign-in-3. The root file is listed by name because a
 * folder list cannot name it.
 */
const SIGN_IN_3_DIRS = ['guide', 'heartbeat'];
const SIGN_IN_3_FILES = ['heartbeat-card.spec.ts'];

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  forbidOnly: true,
  workers: 1,
  retries: 0,
  timeout: 45_000,
  expect: { timeout: 10_000 },
  globalTimeout: Number(process.env['OCUTALON_E2E_TIMEOUT_MS'] ?? 300_000),
  reporter: jsonReport ? [['list'], ['json', { outputFile: jsonReport }]] : [['list']],
  // A unit keeps its own results: ci/iris.sh sets OCUTALON_E2E_OUTPUT to test-results/<unit>, so a later unit of the same job does not clear them.
  outputDir: process.env['OCUTALON_E2E_OUTPUT'] || 'test-results',
  use: {
    baseURL: process.env['OCUTALON_URL'],
    trace: keepTraces ? { mode: 'retain-on-failure', screenshots: false } : 'off',
    screenshot: 'off',
  },
  projects: [
    {
      name: 'chromium',
      testDir: './e2e',
      testIgnore: ['**/e2e/demo-path/**', '**/e2e/demo-switch/**', '**/e2e/floor/**', '**/e2e/answers/**', '**/e2e/cards/**', ...SIGN_IN_2_DIRS.map((dir) => `**/e2e/${dir}/**`), ...SIGN_IN_3_DIRS.map((dir) => `**/e2e/${dir}/**`), ...SIGN_IN_3_FILES.map((file) => `**/e2e/${file}`)],
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'sign-in-2',
      testDir: './e2e',
      testMatch: SIGN_IN_2_DIRS.map((dir) => `**/e2e/${dir}/**/*.@(spec|test).?(c|m)[jt]s?(x)`),
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'sign-in-3',
      testDir: './e2e',
      testMatch: [...SIGN_IN_3_DIRS.map((dir) => `**/e2e/${dir}/**/*.@(spec|test).?(c|m)[jt]s?(x)`), ...SIGN_IN_3_FILES.map((file) => `**/e2e/${file}`)],
      use: { ...devices['Desktop Chrome'] },
    },
    { name: 'demo-path', testDir: './e2e/demo-path', use: { ...devices['Desktop Chrome'] } },
    { name: 'demo-switch', testDir: './e2e/demo-switch', use: { ...devices['Desktop Chrome'] } },
    { name: 'floor', testDir: './e2e/floor', use: { ...devices['Desktop Chrome'] } },
    { name: 'answers', testDir: './e2e/answers', use: { ...devices['Desktop Chrome'] } },
    { name: 'cards', testDir: './e2e/cards', use: { ...devices['Desktop Chrome'] } },
    { name: 'floor-firefox', testDir: './e2e/floor', grep: /@browsers/, use: { ...devices['Desktop Firefox'] } },
    { name: 'floor-webkit', testDir: './e2e/floor', grep: /@browsers/, use: { ...devices['Desktop Safari'] } },
    // online-demo: the specs of e2e-online/ (the online-demo unit, docker/tests/test-online-demo.sh, on a flag-on throwaway), Desktop Chrome,
    // except those of e2e-online/session/, which are the online-session project's, those of e2e-online/allowance/, which are the
    // online-allowance project's, those of e2e-online/demo-path/, which are the online-demo-path project's, and those of
    // e2e-online/visitors/, which are the online-visitors project's. Its folder lies outside e2e/, so the chromium project never runs either.
    {
      name: 'online-demo',
      testDir: './e2e-online',
      testIgnore: ['**/e2e-online/session/**', '**/e2e-online/allowance/**', '**/e2e-online/demo-path/**', '**/e2e-online/visitors/**'],
      use: { ...devices['Desktop Chrome'], ...ONLINE_WAITS },
      metadata: { irisScriptMs: ONLINE_IRIS_SCRIPT_MS },
    },
    // online-session: the specs of e2e-online/session/ (the online-session unit, docker/tests/test-online-session.sh, on its own flag-on
    // throwaway), Desktop Chrome.
    {
      name: 'online-session',
      testDir: './e2e-online/session',
      use: { ...devices['Desktop Chrome'], ...ONLINE_WAITS },
      metadata: { irisScriptMs: ONLINE_IRIS_SCRIPT_MS },
    },
    // online-allowance: the specs of e2e-online/allowance/ (the online-allowance unit, docker/tests/test-online-allowance.sh, on its own flag-on
    // throwaway, because the daily cap is instance-wide), Desktop Chrome.
    {
      name: 'online-allowance',
      testDir: './e2e-online/allowance',
      use: { ...devices['Desktop Chrome'], ...ONLINE_WAITS },
      metadata: { irisScriptMs: ONLINE_IRIS_SCRIPT_MS },
    },
    // online-demo-path: the specs of e2e-online/demo-path/ (the online-demo-path unit, docker/tests/test-online-demo-path.sh, on its own
    // flag-on throwaway with the runners' model keys at the CI mock), Desktop Chrome.
    {
      name: 'online-demo-path',
      testDir: './e2e-online/demo-path',
      use: { ...devices['Desktop Chrome'], ...ONLINE_WAITS },
      metadata: { irisScriptMs: ONLINE_IRIS_SCRIPT_MS },
    },
    // online-visitors: the specs of e2e-online/visitors/ (the online-visitors unit, docker/tests/test-online-visitors.sh, on its own flag-on
    // throwaway whose proxy address is the address IRIS sees for the host's requests, Story 29.7), Desktop Chrome.
    {
      name: 'online-visitors',
      testDir: './e2e-online/visitors',
      use: { ...devices['Desktop Chrome'], ...ONLINE_WAITS },
      metadata: { irisScriptMs: ONLINE_IRIS_SCRIPT_MS },
    },
  ],
});
