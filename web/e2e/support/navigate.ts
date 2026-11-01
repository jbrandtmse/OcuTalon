import type { Page, Response } from '@playwright/test';

/** What gotoSettled needs of a page: its goto. */
export type Navigable = Pick<Page, 'goto'>;

/** The one error that a navigation may retry: the browser's network changed while the page loaded (DW-415). */
const NETWORK_CHANGED = /net::ERR_NETWORK_CHANGED\b/;

/**
 * Navigates the page like page.goto and answers what it answers. When the navigation fails with net::ERR_NETWORK_CHANGED it logs
 * `NAV retry <url>` and navigates once more; the second failure, and every other error (a refused connection, a timeout), is thrown unchanged.
 */
export async function gotoSettled(page: Navigable, url: string, options?: Parameters<Page['goto']>[1]): Promise<Response | null> {
  try {
    return await page.goto(url, options);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!NETWORK_CHANGED.test(message)) throw error;
    console.log(`NAV retry ${url}`);
    return page.goto(url, options);
  }
}
