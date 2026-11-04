import { defineConfig, devices } from '@playwright/test';

import base from './playwright.config';

/**
 * The README picture's capture (docker/tests/record-screenshot.sh, Story 31.3), a manual tool: nothing in CI sees it. Its spec lives in
 * e2e-capture/, a folder outside e2e/ and e2e-online/, and this config is named by no test unit, so the chromium project, playwright.config.ts
 * and CI's browser units never run it. The reporters, the global timeout, the worker count and the base address are the base config's.
 *
 *   capture-setup   the demo-path steps 1 to 5 of e2e/demo-path/ (the journey up to an approved, resolved incident), Desktop Chrome;
 *   capture         every spec under e2e-capture/, after capture-setup, Desktop Chrome.
 */
export default defineConfig({
  ...base,
  projects: [
    { name: 'capture-setup', testDir: './e2e/demo-path', testMatch: /0[1-5]-[^/]*\.spec\.ts$/, use: { ...devices['Desktop Chrome'] } },
    { name: 'capture', testDir: './e2e-capture', dependencies: ['capture-setup'], use: { ...devices['Desktop Chrome'] } },
  ],
});
