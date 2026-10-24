import { defineConfig, devices } from '@playwright/test';

/**
 * Browser specs against a running stack. OCUTALON_URL is its origin, for example http://127.0.0.1:52800; the specs
 * open paths below it, such as /ocutalon/. One worker: the specs share one IRIS instance and its licence.
 *
 * Three projects, all Desktop Chrome:
 *   chromium   every spec under e2e/ except e2e/demo-path/ and e2e/floor/ (the sign-in and API units);
 *   demo-path  the step specs of e2e/demo-path/ (the demo-path unit, docker/tests/test-demo-path.sh);
 *   floor      the accessibility floor's specs of e2e/floor/ (the floor unit, docker/tests/test-floor.sh).
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
      testIgnore: ['**/e2e/demo-path/**', '**/e2e/floor/**'],
      use: { ...devices['Desktop Chrome'] },
    },
    { name: 'demo-path', testDir: './e2e/demo-path', use: { ...devices['Desktop Chrome'] } },
    { name: 'floor', testDir: './e2e/floor', use: { ...devices['Desktop Chrome'] } },
  ],
});
