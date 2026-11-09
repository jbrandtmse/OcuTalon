import { expect as baseExpect, test as base, type APIRequest, type BrowserContext, type Page } from '@playwright/test';

import { boundedStep, capToDeadline, diagnosedAtBound, effectiveWaits, firstAttemptMs, markTestStart, reportRetry, waitsFor } from './bounds';
import { closeDiagnosis, closeLines, closeTargetAgain, describeReclose, printDiagnosis, redactLine, watchRequests, type RequestWatch } from './diagnose';

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
 *
 * Its third contract: every test is marked with the time it began (bounds.ts markTestStart), so that a bounded wait never outlasts the time
 * the test has left less its clean-up reserve (capToDeadline). The `expect` exported here is Playwright's, except that expect.poll with a
 * timeout of its own polls no longer than that cap either, so a poll cannot use up the reserve that the spec's `finally` needs.
 *
 * Its fourth contract: page.close() on a page of the test's context takes no timeout in Playwright, so it is bounded here by the action
 * wait in force (and by the time the test has left, bounds.ts boundedStep) and fails naming `page.close`. When the bound passes, the
 * close diagnosis (diagnose.ts closeDiagnosis, DW-774) prints whether the page, its renderer and the browser still answer, what the page has in
 * flight and the host's load, to close-diagnosis.txt and stdout, before the same error is thrown. A close is retried at most once, and only
 * in Chromium with a bound of 20 s or more (bounds.ts firstAttemptMs): when the page is still open and the close has not settled by half of the
 * bound, the `RETRY <spec>:<line> page.close` line and the redacted lines of the close diagnosis are logged (bounds.ts reportRetry, not
 * printed), and the browser is asked to close the page's target again (diagnose.ts closeTargetAgain); only a refused or unmeasured re-close
 * prints one `DIAG page.close re-close ...` line. The close then ends when the first close settles or the page's `close` event fires, and no
 * later than the bound, which the retry does not change: a second miss fails with the same error and the same diagnosis as a close that was
 * never retried, and a first close that rejects rejects with its own error.
 *
 * Its fifth contract (DW-706): an APIRequestContext made without a timeout of its own (the built-in `request` fixture, a
 * `playwright.request.newContext()` in a spec or a helper) waits no longer than the action wait in force, bounds.ts effectiveWaits: in a
 * test, the project's or the test's actionTimeout, else a share of the test's timeout (waitsFor); in a hook, the project's actionTimeout, else
 * the action cap. A call that never answers then fails with Playwright's call name (apiRequestContext.get: Timeout ...ms exceeded) before the
 * test timeout. An explicit `timeout` option (0 included) is kept. A context's timeout is fixed when it is made, so a test that raises its
 * timeout later keeps the earlier wait for a context made before.
 */

/**
 * The first close of a page, with one more close of its target when it is still open and unsettled by half of boundMs (see the fourth contract
 * above). Settles with the first close, or when the page closes; it settles at once, with no retry, for a bound under 20 s, a page that is not
 * Chromium, or a first close that ends first. The bound itself is the caller's.
 */
function closeWithOneMore(page: Page, first: Promise<void>, boundMs: number, watch: RequestWatch): Promise<void> {
  let firstMs: number | undefined;
  try {
    firstMs = page.context().browser()?.browserType().name() === 'chromium' ? firstAttemptMs(capToDeadline(boundMs).ms) : undefined;
  } catch {
    firstMs = undefined;
  }
  if (firstMs === undefined) return first;
  return new Promise<void>((resolve, reject) => {
    let ended = false;
    const end = (): void => {
      ended = true;
      clearTimeout(timer);
      page.off('close', onClose);
    };
    const onClose = (): void => {
      end();
      resolve();
    };
    const again = async (): Promise<void> => {
      let lines: string[] = [];
      try {
        lines = await closeLines(page, watch);
      } catch {
        // The retry goes on without its diagnosis.
      }
      // While the page was probed, the first close may have settled or the page may have closed.
      if (ended || page.isClosed()) return;
      reportRetry('page.close', lines.map(redactLine));
      const line = describeReclose(await closeTargetAgain(page));
      if (line !== undefined) printDiagnosis([line], 'close-diagnosis');
    };
    const timer = setTimeout(() => void again().catch(() => undefined), firstMs);
    page.on('close', onClose);
    first.then(
      () => {
        end();
        resolve();
      },
      (error: unknown) => {
        end();
        reject(error);
      },
    );
  });
}

/** Makes the page's close() reject with `page.close: no answer within <s> s` when the page has not closed within waitMs() (at the time of the call); see closeWithOneMore for the one re-close. */
export function boundedClose(page: Page, waitMs: () => number): void {
  const close = page.close.bind(page);
  const watch = watchRequests(page);
  page.close = (options) => diagnosedAtBound(boundedStep(closeWithOneMore(page, close(options), waitMs(), watch), waitMs(), 'page.close'), 'page.close', () => closeDiagnosis(page, watch));
}

type PollOptions = { timeout?: number } | string | undefined;

/** Playwright's expect, whose poll caps an explicit timeout at the running test's deadline (bounds.ts capToDeadline). */
export const expect = new Proxy(baseExpect, {
  get(target, key, receiver) {
    const value: unknown = Reflect.get(target, key, receiver);
    if (key !== 'poll' || typeof value !== 'function') return value;
    return (generator: unknown, options?: PollOptions) => {
      const timeout = typeof options === 'object' ? options.timeout : undefined;
      const capped = timeout ? { ...(options as object), timeout: capToDeadline(timeout).ms } : options;
      return (value as (generator: unknown, options?: PollOptions) => unknown).call(target, generator, capped);
    };
  },
});

/** Removes every route of the target and lets the callbacks in flight end quietly; a target that is already closed has none to remove. */
async function unroute(target: Page | BrowserContext): Promise<void> {
  try {
    await target.unrouteAll({ behavior: 'ignoreErrors' });
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes('has been closed')) throw error;
  }
}

/** What the running test says about its waits, for requestWait; set by the auto fixture `requestWaitSource` and cleared when the test ends. */
let waitSource: { timeout: () => number; use: { actionTimeout?: number; navigationTimeout?: number } } | undefined;

/** The action wait, in ms, that an APIRequestContext made now gets when its maker passes no timeout (see the fifth contract above). */
export function requestWait(): number {
  if (waitSource) return effectiveWaits(waitSource.timeout(), waitSource.use).action;
  let use: { actionTimeout?: number; navigationTimeout?: number } | undefined;
  try {
    use = base.info().project.use;
  } catch {
    use = undefined;
  }
  return effectiveWaits(0, use).action;
}

export const test = base.extend<{ testClock: void; requestWaitSource: void }, { requestWaits: void }>({
  requestWaits: [
    async ({ playwright }, use) => {
      const request: APIRequest = playwright.request;
      const original = request.newContext;
      request.newContext = function (this: APIRequest, options?: Parameters<APIRequest['newContext']>[0]) {
        return original.call(this, options?.timeout !== undefined ? options : { ...options, timeout: requestWait() });
      };
      await use();
      request.newContext = original;
    },
    { scope: 'worker', auto: true },
  ],
  requestWaitSource: [
    async ({ actionTimeout, navigationTimeout }, use, testInfo) => {
      waitSource = { timeout: () => testInfo.timeout, use: { actionTimeout, navigationTimeout } };
      await use();
      waitSource = undefined;
    },
    { auto: true },
  ],
  testClock: [
    async ({}, use, testInfo) => {
      markTestStart(testInfo);
      await use();
    },
    { auto: true },
  ],
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
    const closeWait = (): number => effectiveWaits(testInfo.timeout, { actionTimeout, navigationTimeout }).action;
    context.on('page', (page) => boundedClose(page, closeWait));
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
