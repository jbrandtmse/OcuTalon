import type { BrowserContext, Page, Response } from '@playwright/test';

/**
 * What the specs of the online-demo project share (Story 16.1). The project runs on the throwaway that docker/tests/test-online-demo.sh
 * starts with the online-demo flag on and the test start values; the unit gives the two public accounts' names and passwords as
 * OCUTALON_DEMOACCOUNT_* and OCUTALON_READONLYACCOUNT_* (fixtureUser reads them).
 */

/** The group-wide sign-out of the sign-in group: it ends the CSP session of /ocutalon, /ocutalon/api and the trace applications. */
export const SIGN_OUT = '/ocutalon/?IRISLogout=end';

/** The sign-out of each trace application, which signOutGroup also sends so that no trace session outlives the case. */
const TRACE_SIGN_OUTS = ['/ocutalon/trace/ocutalon/?IRISLogout=end', '/ocutalon/trace/ocuorders/?IRISLogout=end'] as const;

/**
 * Signs the context out of the whole sign-in group. Every spec calls it in `finally`, because a signed-in CSP session holds one of the
 * stack's licence connections until it times out (28,800 s on a throwaway). A failed sign-out is not a failure of the case.
 */
export async function signOutGroup(target: Page | BrowserContext): Promise<void> {
  const context = 'context' in target && typeof target.context === 'function' ? target.context() : (target as BrowserContext);
  for (const path of [SIGN_OUT, ...TRACE_SIGN_OUTS]) {
    try {
      await context.request.get(path);
    } catch {
      /* The context may be closed already. */
    }
  }
}

let probes = 0;
/** The splash's address with a probe that no other request of the run used (the unit's test discipline). */
const probedSplash = (): string => `/ocutalon/?probe=${Date.now()}${(probes += 1)}`;

/**
 * Signs in from the splash at path (by default the splash with a fresh probe): it opens the page, fills a field only when its value is
 * given (the exact labels "User name" and "Password"; the fields are prefilled with the published values), presses **Sign in and
 * start** and returns the server's answer to the form. The caller then asserts what the next page shows, with an assertion that waits
 * for it.
 */
export async function signInFromSplash(page: Page, user?: string, password?: string, path = probedSplash()): Promise<Response> {
  await page.goto(path);
  if (user !== undefined) await page.getByLabel('User name', { exact: true }).fill(user);
  if (password !== undefined) await page.getByLabel('Password', { exact: true }).fill(password);
  const answered = page.waitForResponse((response) => response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Sign in and start', exact: true }).click();
  return answered;
}

/**
 * Before the page's scripts run: records every text that the splash's one polite live region (#ocu-live) receives, each node added to
 * it, as window.announced, so that a case can count how often a message was announced. The CDK announcer's recorder of support/page.ts
 * does not see this region: it watches the announcer's own element.
 */
export async function recordSplashAnnouncements(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const announced: string[] = [];
    (window as unknown as { announced: string[] }).announced = announced;
    new MutationObserver((records) => {
      for (const record of records) {
        if (!(record.target instanceof HTMLElement) || record.target.id !== 'ocu-live') continue;
        for (const node of Array.from(record.addedNodes)) {
          if (node.textContent) announced.push(node.textContent);
        }
      }
    }).observe(document, { subtree: true, childList: true });
  });
}

/** The texts that the splash's live region received so far, in order (recordSplashAnnouncements). */
export function splashAnnouncements(page: Page): Promise<string[]> {
  return page.evaluate(() => [...((window as unknown as { announced?: string[] }).announced ?? [])]);
}
