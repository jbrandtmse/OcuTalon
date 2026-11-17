import { test, type Page, type Response } from '@playwright/test';

// The extension: web/scripts/goto-settled.test.mjs imports this file straight into Node, which resolves no extensionless relative import.
import { capToDeadline, effectiveWaits, reportSlow, secs } from './bounds.ts';

/** What gotoSettled needs of a page: its goto, its URL and the wait for a URL. */
export type Navigable = Pick<Page, 'goto' | 'url' | 'waitForURL'>;

/** The errors that a navigation may retry once: the browser's network changed while the page loaded (DW-415), or the page's own location.replace aborted the navigation (DW-690). */
const RETRYABLE = /net::ERR_(?:NETWORK_CHANGED|ABORTED)\b/;

/** The error that leaves a failed navigation's error page behind: Chromium commits that page a moment after the goto rejects. */
const NETWORK_CHANGED = /net::ERR_NETWORK_CHANGED\b/;

/** The URL of Chromium's error page for a navigation that failed. */
const CHROME_ERROR_URL = 'chrome-error://chromewebdata/';

/** The action and navigation waits, in ms, that a helper bounds a step with. */
export interface Waits {
  action: number;
  navigation: number;
}

/**
 * The waits in force for the running test: the project's actionTimeout and navigationTimeout when it sets them (the online projects), else
 * the shared test's defaults for the test's timeout (bounds.ts waitsFor). Undefined outside a test.
 */
export function currentWaits(): Waits | undefined {
  try {
    const info = test.info();
    return effectiveWaits(info.timeout, info.project.use);
  } catch {
    return undefined;
  }
}

/**
 * Navigates the page like page.goto and answers what it answers, within its own bound (the options' timeout, 0 for none, else the navigation
 * wait in force, currentWaits) and never past the running test's deadline (bounds.ts capToDeadline). A navigation that does not finish in
 * time throws `gotoSettled: no answer within <s> s from <url>`. When it fails with net::ERR_NETWORK_CHANGED or net::ERR_ABORTED it logs
 * `NAV retry <url> after <the first line of the first error>` and navigates once more, under the bound of the time left; the second
 * failure, and every other error (a refused connection), is thrown unchanged. After net::ERR_NETWORK_CHANGED the retry waits first for the
 * failed navigation's own error page (`chrome-error://chromewebdata/`, committed), within the time left in the navigation bound, because a
 * goto made before that commit is interrupted by it; an error page that does not show in that time throws
 * `gotoSettled: the failed navigation's error page did not show within <s> s from <url>` with the first error as its cause, and no second
 * goto. net::ERR_ABORTED leaves no error page and is retried at once. A navigation that took 10 s or more and did not time out prints a
 * SLOW line.
 */
export async function gotoSettled(page: Navigable, url: string, options?: Parameters<Page['goto']>[1]): Promise<Response | null> {
  const own = options?.timeout === undefined ? currentWaits()?.navigation : options.timeout || Infinity;
  const beganAt = Date.now();
  const go = async (): Promise<Response | null> => {
    const capped = own === undefined ? undefined : capToDeadline(own);
    const bound = capped !== undefined && Number.isFinite(capped.ms) ? capped : undefined;
    const startedAt = Date.now();
    let timedOut = false;
    try {
      return await page.goto(url, bound === undefined ? options : { ...options, timeout: bound.ms });
    } catch (error) {
      if (bound !== undefined && error instanceof Error && error.name === 'TimeoutError') {
        timedOut = true;
        throw new Error(`gotoSettled: no answer within ${secs(bound.ms)} s from ${url}${bound.note}\n${error.message}`, { cause: error });
      }
      throw error;
    } finally {
      if (!timedOut) reportSlow(`gotoSettled ${url}`, startedAt);
    }
  };
  try {
    return await go();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!RETRYABLE.test(message)) throw error;
    if (NETWORK_CHANGED.test(message)) await errorPageShown(page, url, error, own === undefined ? undefined : Math.min(capToDeadline(own).ms, own - (Date.now() - beganAt)));
    console.log(`NAV retry ${url} after ${message.split('\n')[0]}`);
    return go();
  }
}

/**
 * Returns once the page is at Chromium's error page of the failed navigation (the URL is checked first, then waited for with
 * `waitUntil: 'commit'`), within leftMs, the time left in gotoSettled's bound (undefined or not finite: the page's own default wait). A page
 * that is not there in time throws the named error, with the first error as its cause.
 */
async function errorPageShown(page: Navigable, url: string, first: unknown, leftMs: number | undefined): Promise<void> {
  if (page.url() === CHROME_ERROR_URL) return;
  const timeout = leftMs !== undefined && Number.isFinite(leftMs) ? Math.max(1, Math.floor(leftMs)) : undefined;
  try {
    await page.waitForURL(CHROME_ERROR_URL, timeout === undefined ? { waitUntil: 'commit' } : { waitUntil: 'commit', timeout });
  } catch {
    const within = timeout === undefined ? "the page's default wait" : `${secs(timeout)} s`;
    throw new Error(`gotoSettled: the failed navigation's error page did not show within ${within} from ${url}`, { cause: first });
  }
}
