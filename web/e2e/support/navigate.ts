import { test, type Page, type Response } from '@playwright/test';

// The extension: web/scripts/goto-settled.test.mjs imports this file straight into Node, which resolves no extensionless relative import.
import { effectiveWaits } from './bounds.ts';

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
 * timeout. A navigation that does not finish in time throws `gotoSettled: no answer within <s> s from <url>`. When it fails with
 * net::ERR_NETWORK_CHANGED or net::ERR_ABORTED it logs `NAV retry <url>` and navigates once more; the second failure, and every other error
 * (a refused connection), is thrown unchanged.
 */
export async function gotoSettled(page: Navigable, url: string, options?: Parameters<Page['goto']>[1]): Promise<Response | null> {
  const wait = options?.timeout === undefined ? currentWaits()?.navigation : undefined;
  const bounded = wait === undefined ? options : { ...options, timeout: wait };
  const go = async (): Promise<Response | null> => {
    try {
      return await page.goto(url, bounded);
    } catch (error) {
      if (wait !== undefined && error instanceof Error && error.name === 'TimeoutError') {
        throw new Error(`gotoSettled: no answer within ${wait / 1000} s from ${url}\n${error.message}`, { cause: error });
      }
      throw error;
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
