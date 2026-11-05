import { test as base, type BrowserContext, type Page } from '@playwright/test';

import { waitsFor } from './bounds';

export * from '@playwright/test';

/**
 * The Playwright `test` that every spec under e2e/ and e2e-online/ imports (web/scripts/route-cleanup.test.mjs names a spec that does not).
 * Its contract: when a test ends, no route callback of its page, of the other pages of its context or of its context is still live. A
 * callback that is still waiting on route.fetch (a poll held on purpose, a request the upstream never answers) would otherwise fail the
 * next test with `route.fetch: Test ended`. The `page` and `context` fixtures unroute in their teardown with unrouteAll({ behavior:
 * 'ignoreErrors' }), which does not wait for a callback in flight and ignores the error it throws when it ends. A page or context that the test already closed is skipped;
 * any other error fails the test. A context from browser.newContext() is not a fixture: its test closes it itself.
 *
 * Its second contract: every page of the test's context has default action and navigation waits shorter than the test's own timeout
 * (bounds.ts waitsFor of the timeout in force, kept current when the test calls test.setTimeout), so a wait that has no timeout of its
 * own, in a helper or in a spec, fails with Playwright's call name and the line of the call and not at the test timeout. A project
 * that sets actionTimeout or navigationTimeout keeps its own, and a wait that passes a timeout keeps that.
 */

/** Removes every route of the target and lets the callbacks in flight end quietly; a target that is already closed has none to remove. */
async function unroute(target: Page | BrowserContext): Promise<void> {
  try {
    await target.unrouteAll({ behavior: 'ignoreErrors' });
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes('has been closed')) throw error;
  }
}

export const test = base.extend({
  page: async ({ page }, use) => {
    await use(page);
    await unroute(page);
  },
  context: async ({ context, actionTimeout, navigationTimeout }, use, testInfo) => {
    const giveWaits = (): void => {
      const waits = waitsFor(testInfo.timeout);
      if (!actionTimeout) context.setDefaultTimeout(waits.actionTimeout);
      if (!navigationTimeout) context.setDefaultNavigationTimeout(waits.navigationTimeout);
    };
    giveWaits();
    const setTestTimeout = testInfo.setTimeout.bind(testInfo);
    testInfo.setTimeout = (timeout: number): void => {
      setTestTimeout(timeout);
      giveWaits();
    };
    await use(context);
    for (const page of context.pages()) await unroute(page);
    await unroute(context);
  },
});
