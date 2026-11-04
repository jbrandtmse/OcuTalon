import { defineConfig, devices } from '@playwright/test';

import base from './playwright.config';

/**
 * The clean-machine rehearsal's browser specs (release/rehearse.sh, Story 11.12): the repeats of runs 2 to N and the tell-now item of every
 * run, in e2e-rehearsal/. They live outside e2e/ and under this config of their own, so the chromium project, playwright.config.ts and CI's
 * browser units never see them. The reporters, the global timeout, the worker count and the base address are the base config's.
 *
 *   rehearsal   every spec under e2e-rehearsal/ (repeat.spec.ts, then tell-now.spec.ts), Desktop Chrome.
 */
export default defineConfig({
  ...base,
  projects: [{ name: 'rehearsal', testDir: './e2e-rehearsal', use: { ...devices['Desktop Chrome'] } }],
});
