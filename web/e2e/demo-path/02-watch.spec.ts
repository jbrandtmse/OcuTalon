import { randomBytes } from 'node:crypto';

import { expect, test } from '@playwright/test';

import { post } from '../support/api';
import { armCountdown, pointKeys } from '../support/devices';
import { BREAK_FEED, breakFeedLeft, breakFeedButton, checkRow, composer, doneTurn, readmeSession, refusal, watchMessage } from '../support/demo-path';
import { replyOf, signInReadmeLoaded } from '../support/floor';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** The hint under an inactive Break the feed before any watch (EXPERIENCE, the demo guide), written out here as the independent oracle of the page's own. */
const NOT_WATCHING = 'Ask OcuTalon to watch the Orders production first (step 1).';

/**
 * UJ-1 step 2 (REL-2, Story 11.1): the watch, on the first-start stack with the model keys pointed at the CI mock (they stay pointed
 * through step 5; 06 puts them back). It runs after 01 and leaves the README session watching the Orders production for 03 to 06.
 *   - Before the watch: Break the feed is inactive with its hint and Do step 1, a press is refused 409 not_watching, and a refused press
 *     sends nothing (no run, no header, no failed order).
 *   - The watch: the guide's watch prompt is sent through the composer behind the marker of the CI mock scenario watch-act-orders, whose
 *     countdown is armed with 1 (AD-22): the Triage request gets reply 0 (Act), the turn replies 1 (start_watch) and 2 (its text). The
 *     reply's strip shows the chip Act with its reason and one trace link, and no Fallback flag. The "Orders production" check row shows,
 *     Break the feed is active, and the guide reads step 1 done and step 2 current.
 *   - The real last run (DW-202): the watch row's first heartbeat run gives its row "Last run ... \u00B7 Passed" within 120 s, followed
 *     by the run's own Trace link.
 * It needs the first-start stack (OCUTALON_URL): without it the group skips as it is declared, before any hook starts, because a run
 * with no stack may have no browser either (the unit tests' demo-path run in the hosted web job), and a skip inside the test would
 * launch one first.
 */
test.describe('Story 11.1: step 1 of the guide watches the Orders production through the chat', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.1 needs the first-start stack (OCUTALON_URL), which a run without one lacks');
  test.describe.configure({ mode: 'serial' });

  test.beforeAll(async () => {
    test.setTimeout(240_000);
    await pointKeys();
  });

  test('before the watch, Break the feed is inactive with its hint, and a press is refused and sends nothing', async ({ page }) => {
    test.setTimeout(120_000);
    const session = await readmeSession();
    await signInReadmeLoaded(page);

    const box = page.locator('app-break-feed-box');
    const button = breakFeedButton(page);
    await expect(button, 'Break the feed is inactive').toHaveAttribute('aria-disabled', 'true');
    await expect(box.locator('.hint'), 'with the hint under it').toHaveText(NOT_WATCHING);
    await expect(box.getByRole('button', { name: 'Do step 1', exact: true }), 'and Do step 1').toBeVisible();

    const pressed = await refusal(await post(page.request, BREAK_FEED, {}));
    expect(pressed, 'a press is refused: nothing is watched').toEqual({ status: 409, code: 'not_watching', message: NOT_WATCHING });
    expect(await breakFeedLeft(session), 'a refused press sends nothing: no run, no header, no failed order').toEqual({ runs: '0:', headers: '0', failed: '0' });
  });

  test('the watch prompt gets its Act reply with its reason and trace link, the check row shows, and Break the feed becomes active', async ({ page }) => {
    test.setTimeout(180_000);
    const key = randomBytes(6).toString('hex');
    await signInReadmeLoaded(page);
    await armCountdown(`watch-act-orders:${key}`, 1);

    await composer(page).fill(watchMessage(key));
    await composer(page).press('Enter');

    const turn = await doneTurn(page);
    const reply = replyOf(page, turn.clientId);
    const strip = reply.locator('app-decision-strip');
    await expect(strip, "the reply's decision strip shows").toHaveCount(1, { timeout: 30_000 });
    await expect(strip.locator('app-outcome-chip .chip'), 'its chip is Act: the mock answered the Triage request with reply 0').toHaveText('Act');
    await expect(strip.locator('app-fallback-flag'), 'with no Fallback flag').toHaveCount(0);
    await expect(strip.locator('.reason').first(), 'it shows its reason').toHaveText('The CI mock acts on the request to watch the Orders production.');
    await expect(strip.locator('app-trace-link a'), 'and one trace link').toHaveCount(1);

    await expect(checkRow(page), 'the "Orders production" check row shows').toHaveCount(1, { timeout: 60_000 });
    await expect(breakFeedButton(page), 'Break the feed is active').not.toHaveAttribute('aria-disabled', 'true', { timeout: 30_000 });
    const guide = page.getByRole('region', { name: 'Demo guide' });
    await expect(guide.getByRole('button', { name: 'Step 1, Watch, done', exact: true }), 'the guide marks step 1 done').toHaveCount(1);
    await expect(guide.getByRole('button', { name: 'Step 2, Reminder, current', exact: true }), 'and step 2 current').toHaveCount(1);
  });

  test('the "Orders production" check row shows a real last run from the heartbeat', async ({ page }) => {
    test.setTimeout(180_000);
    await signInReadmeLoaded(page);
    const row = checkRow(page);
    await expect(row, 'the watch row is there').toHaveCount(1);
    await expect(row.locator('.meta'), "the heartbeat's Checks run gives it a last run and its result").toHaveText(/^Last run \S.* \u00B7 Passed( \u00B7 Trace \(opens in a new tab\))?$/, { timeout: 120_000 });
  });
});
