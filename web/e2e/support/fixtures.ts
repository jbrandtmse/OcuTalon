import { test as base, type BrowserContext, type Page } from '@playwright/test';

export * from '@playwright/test';

/**
 * The Playwright `test` that every spec under e2e/ and e2e-online/ imports (web/scripts/route-cleanup.test.mjs names a spec that does not).
 * Its contract: when a test ends, no route callback of its page, of the other pages of its context or of its context is still live. A
 * callback that is still waiting on route.fetch (a poll held on purpose, a request the upstream never answers) would otherwise fail the
 * next test with `route.fetch: Test ended`. The `page` and `context` fixtures unroute in their teardown with unrouteAll({ behavior:
 * 'ignoreErrors' }), which does not wait for a callback in flight and ignores the error it throws when it ends. A page or context that the test already closed is skipped;
 * any other error fails the test. A context from browser.newContext() is not a fixture: its test closes it itself.
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
  context: async ({ context }, use) => {
    await use(context);
    for (const page of context.pages()) await unroute(page);
    await unroute(context);
  },
});
