import { defineConfig, devices } from '@playwright/test';

/**
 * Browser specs against a running stack. OCUTALON_URL is its origin, for example http://127.0.0.1:52800; the specs
 * open paths below it, such as /ocutalon/. One worker: the specs share one IRIS instance and its licence.
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  forbidOnly: true,
  workers: 1,
  retries: 0,
  timeout: 45_000,
  expect: { timeout: 10_000 },
  globalTimeout: Number(process.env['OCUTALON_E2E_TIMEOUT_MS'] ?? 300_000),
  reporter: [['list']],
  outputDir: 'test-results',
  use: {
    baseURL: process.env['OCUTALON_URL'],
    trace: 'off',
    screenshot: 'off',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
