import { test, type Page, type Response } from '@playwright/test';

// The extension: web/scripts/goto-settled.test.mjs imports this file straight into Node, which resolves no extensionless relative import.
import { capToDeadline, effectiveWaits, reportSlow, secs } from './bounds.ts';

/** What gotoSettled needs of a page: its goto. */
export type Navigable = Pick<Page, 'goto'>;

/** The errors that a navigation may retry once: the browser's network changed while the page loaded (DW-415), or the page's own location.replace aborted the navigation (DW-690). */
const RETRYABLE = /net::ERR_(?:NETWORK_CHANGED|ABORTED)\b/;

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
 * `NAV retry <url>` and navigates once more, under the bound of the time left; the second failure, and every other error (a refused
 * connection), is thrown unchanged. A navigation that took 10 s or more and did not time out prints a SLOW line.
 */
export async function gotoSettled(page: Navigable, url: string, options?: Parameters<Page['goto']>[1]): Promise<Response | null> {
  const own = options?.timeout === undefined ? currentWaits()?.navigation : options.timeout || Infinity;
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
    console.log(`NAV retry ${url}`);
    return go();
  }
}
