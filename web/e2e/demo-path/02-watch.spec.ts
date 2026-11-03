import { expect, test } from '@playwright/test';

import { post } from '../support/api';
import { pointKeys } from '../support/devices';
import { BREAK_FEED, ON_MOCK, breakFeedButton, breakFeedLeft, checkRow, readmeSession, refusal, watchThroughGuide } from '../support/demo-path';
import { signInReadmeLoaded } from '../support/floor';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** The hint under an inactive Break the feed before any watch (EXPERIENCE, the demo guide), written out here as the independent oracle of the page's own. */
const NOT_WATCHING = 'Ask OcuTalon to watch the Orders production first (step 1).';

/**
 * UJ-1 step 2 (REL-2, Stories 11.1 and 11.7): the watch, on the first-start stack. On the CI mock the model keys are pointed at the mock
 * (they stay pointed until 08 puts them back); on the real model (OCUTALON_DEMO_PATH_MODEL=real) the specs leave the keys alone.
 * It runs after 01 and leaves the README session watching the Orders production for 03 to 08.
 *   - Before the watch: Break the feed is inactive with its hint and Do step 1, a press is refused 409 not_watching, and a refused press
 *     sends nothing (no run, no header, no failed order).
 *   - The watch: the guide's own Send at step 1 sends the watch prompt (support/demo-path.ts watchThroughGuide). The reply's strip passes
 *     expectDecision; on the mock it shows the chip Act with its reason (the mock's guide-watch-triage scenario, selected by the prompt
 *     and the Triage mock key, AD-22), and the turn's text follows the mock's start_watch call. The "Orders production" check row shows,
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
    if (ON_MOCK) await pointKeys();
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

  test("the guide's Send for step 1 gets a decision with its reason and trace link (Act on the CI mock), the check row shows, and Break the feed becomes active", async ({ page }) => {
    test.setTimeout(180_000);
    await signInReadmeLoaded(page);
    await watchThroughGuide(page);
  });

  test('the "Orders production" check row shows a real last run from the heartbeat', async ({ page }) => {
    test.setTimeout(180_000);
    await signInReadmeLoaded(page);
    const row = checkRow(page);
    await expect(row, 'the watch row is there').toHaveCount(1);
    await expect(row.locator('.meta'), "the heartbeat's Checks run gives it a last run and its result").toHaveText(/^Last run \S.* \u00B7 Passed( \u00B7 Trace \(opens in a new tab\))?$/, { timeout: 120_000 });
  });
});
