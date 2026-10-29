import { defineConfig, devices } from '@playwright/test';

/**
 * Browser specs against a running stack. OCUTALON_URL is its origin, for example http://127.0.0.1:52800; the specs
 * open paths below it, such as /ocutalon/. One worker: the specs share one IRIS instance and its licence.
 *
 * Nine projects:
 *   chromium       every spec under e2e/ except e2e/demo-path/, e2e/demo-switch/, e2e/floor/, e2e/answers/ and e2e/cards/ (the sign-in and API units), Desktop Chrome;
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
 *   online-demo    the specs of e2e-online/ outside e2e-online/session/ (the online-demo unit, docker/tests/test-online-demo.sh), Desktop Chrome;
 *   online-session the specs of e2e-online/session/ (the online-session unit, docker/tests/test-online-session.sh): leaving the page and
 *                  Sign out on a flag-on stack, Story 16.4, Desktop Chrome.
 * The floor unit runs the three floor projects one after the other on its one stack (the e2e:floor script), Chromium first.
 * When OCUTALON_E2E_JSON names a file, a JSON report is written there beside the list reporter.
 */
const jsonReport = process.env['OCUTALON_E2E_JSON'];

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
  outputDir: 'test-results',
  use: {
    baseURL: process.env['OCUTALON_URL'],
    trace: 'off',
    screenshot: 'off',
  },
  projects: [
    {
      name: 'chromium',
      testDir: './e2e',
      testIgnore: ['**/e2e/demo-path/**', '**/e2e/demo-switch/**', '**/e2e/floor/**', '**/e2e/answers/**', '**/e2e/cards/**'],
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
    // except those of e2e-online/session/, which are the online-session project's. Its folder lies outside e2e/, so the chromium project
    // never runs either.
    { name: 'online-demo', testDir: './e2e-online', testIgnore: ['**/e2e-online/session/**'], use: { ...devices['Desktop Chrome'] } },
    // online-session: the specs of e2e-online/session/ (the online-session unit, docker/tests/test-online-session.sh, on its own flag-on
    // throwaway), Desktop Chrome.
    { name: 'online-session', testDir: './e2e-online/session', use: { ...devices['Desktop Chrome'] } },
  ],
});
