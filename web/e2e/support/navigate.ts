import { test, type Page, type Response } from '@playwright/test';

// The extension: web/scripts/goto-settled.test.mjs imports this file straight into Node, which resolves no extensionless relative import.
import { capToDeadline, effectiveWaits, reportSlow } from './bounds.ts';

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
 * Navigates the page like page.goto and answers what it answers, within the navigation wait in force (currentWaits) unless the options carry a
 * timeout, and never later than the running test's timeout minus bounds.ts DEADLINE_MARGIN_MS (capToDeadline). A navigation that does not
 * finish in time throws `gotoSettled: no answer within <s> s from <url>`. When it fails with net::ERR_NETWORK_CHANGED or net::ERR_ABORTED it
 * logs `NAV retry <url>` and navigates once more, under the bound of the time left; the second failure, and every other error (a refused
 * connection), is thrown unchanged.
 */
export async function gotoSettled(page: Navigable, url: string, options?: Parameters<Page['goto']>[1]): Promise<Response | null> {
  const own = options?.timeout === undefined ? currentWaits()?.navigation : undefined;
  const go = async (): Promise<Response | null> => {
    const capped = own === undefined ? undefined : capToDeadline(own);
    const startedAt = Date.now();
    try {
      return await page.goto(url, capped === undefined ? options : { ...options, timeout: capped.ms });
    } catch (error) {
      if (capped !== undefined && error instanceof Error && error.name === 'TimeoutError') {
        throw new Error(`gotoSettled: no answer within ${capped.ms / 1000} s from ${url}${capped.note}\n${error.message}`, { cause: error });
      }
      throw error;
    } finally {
      reportSlow(`gotoSettled ${url}`, startedAt);
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
