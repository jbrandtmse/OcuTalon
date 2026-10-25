import type { BrowserContext, Page } from '@playwright/test';

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
