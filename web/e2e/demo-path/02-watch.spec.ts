import { notBuilt } from './not-built';

/** UJ-1 step 2: the watch prompt and the background check. */
notBuilt('the watch prompt gets its reply, with the attention decision, its reasons and its trace link', '4.7');
notBuilt('the background check "Orders production" appears, and Break the feed becomes active', '4.7');
notBuilt('the "Orders production" check row shows a real last run', '8.2');

import { expect as heartbeatExpect, test as heartbeatTest } from '@playwright/test';

import { signInReadme as heartbeatSignIn } from '../sign-in/helpers';
import { changeSnapshot as heartbeatSnapshot } from '../support/api';

/**
 * Story 8.2, with a fixture row (AD-29: Checks is not built here): the page's /state is the real answer with one "Orders production"
 * check row added to the rail, whose last run was 30 seconds ago. The real status array, which the answer keeps, holds no
 * heartbeatStalled, so the row shows its last run and Passed, with no "(late)" mark and no heartbeat banner. The test above that
 * stays skipped until the integration switch replaces it with the real watch's row.
 */
heartbeatTest.describe('Story 8.2: the check row while the heartbeat is not stalled (fixture row)', () => {
  heartbeatTest('a fixture "Orders production" row shows its last run with no late mark while the real status holds no heartbeatStalled', async ({ page }) => {
    heartbeatTest.skip(!process.env['OCUTALON_URL'], 'Story 8.2 needs the first-start stack (OCUTALON_URL), which a run without one lacks');
    let realStatus: Array<{ condition: string }> | undefined;
    await heartbeatSnapshot(page, (snapshot) => {
      realStatus = snapshot['status'] as Array<{ condition: string }>;
      const rail = snapshot['rail'] as { checks: unknown[] };
      rail.checks = [
        {
          ref: 'zz-fixture-orders',
          kind: 'production',
          displayName: 'Orders',
          lastRunAt: new Date(Date.now() - 30_000).toISOString().replace(/\.\d{3}Z$/, 'Z'),
          result: 'passed',
        },
      ];
    });
    await heartbeatSignIn(page);
    await heartbeatExpect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

    heartbeatExpect(realStatus, "the real /state answered, and its status holds no heartbeatStalled").toBeDefined();
    heartbeatExpect((realStatus ?? []).map((one) => one.condition)).not.toContain('heartbeatStalled');
    const row = page.getByRole('region', { name: 'Status', exact: true }).locator('li.row').filter({ hasText: 'Orders production' });
    await heartbeatExpect(row, 'the fixture row is listed').toHaveCount(1);
    await heartbeatExpect(row.locator('.meta'), 'it reads its last run and its result').toHaveText(/^Last run \S.* \u00B7 Passed$/);
    await heartbeatExpect(row.locator('.meta'), 'with no late mark').not.toContainText('(late)');
    await heartbeatExpect(page.locator('app-banner-stack [data-banner="heartbeatStalled"]'), 'and no heartbeat banner shows').toHaveCount(0);
  });
});
