import { expect, test, type Page } from '@playwright/test';

import { STATE } from '../../e2e/support/api';
import { recordTraffic } from '../../e2e/support/clock';
import { accountTrigger, advance, epochOf, landedOn, openSession, removeSession, signOutGroup } from '../support';

/**
 * Story 16.4, what does not count as activity for the idle cap (matrix row 5; AC 3), on the throwaway of
 * docker/tests/test-online-session.sh. leave.spec.ts L2 shows that a key press and a click keep the page; this case shows the other half of the
 * clause "only a key press, a click and a sent message count; polls, snapshots, timers and pointer movement never do".
 * - L7: on the page's own clock, 580 s with no activity, then pointer movement over the page, a scroll of the wheel and a focus change, then
 *   the clock runs on with the wall clock past 600 s since the page loaded (so that the group sign-out's 3 s bound is real time): the page
 *   frees its place all the same, lands on the splash with its load time and the place-freed notice, and its CSP session is gone.
 * The case signs out of the whole sign-in group and removes its rows in `finally`. The texts are written out here, as the independent oracle of
 * the page's own. openSession, advance and epochOf are the online-demo support's.
 */
test.describe.configure({ timeout: 300_000 });

const PLACE_FREED = 'You were away for a while, so your place was freed for other visitors. Sign in again to pick up where you left off.';
const CAP_MS = 600_000;

const mainOf = (page: Page) => page.locator('main.main');

test('L7: pointer movement, a scroll and a focus change are no activity: the page frees its place at 600 s all the same', async ({ page, context }) => {
  let epoch = '';
  try {
    await recordTraffic(page);
    await page.clock.install();
    epoch = await openSession(page);
    const loadedAt = await page.evaluate(() => Date.now());

    await advance(page, CAP_MS - 20_000);
    await expect(mainOf(page), '580 s with no activity: still on the page').toHaveAttribute('data-snapshot', 'loaded');
    await page.mouse.move(120, 160);
    await page.mouse.move(420, 360, { steps: 6 });
    await page.mouse.wheel(0, 400);
    await accountTrigger(page).focus();
    await expect(accountTrigger(page), 'the focus moved to the account trigger').toBeFocused();
    await expect(mainOf(page), 'and the page is still there').toHaveAttribute('data-snapshot', 'loaded');

    await landedOn(page, /\/ocutalon\/\?since=/, 60_000);
    const url = new URL(page.url());
    expect(url.pathname, 'the splash').toBe('/ocutalon/');
    const since = Date.parse(url.searchParams.get('since') ?? '');
    expect(Number.isNaN(since) ? Number.NaN : Math.abs(since - loadedAt), 'since is the time the page loaded, to the second').toBeLessThan(5000);
    await expect(page.locator('#ocu-notice'), 'the notice reads the place-freed text').toHaveText(PLACE_FREED);
    await page.clock.resume();
    expect((await context.request.get(STATE)).status(), "the context's /state is 401").toBe(401);
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});
