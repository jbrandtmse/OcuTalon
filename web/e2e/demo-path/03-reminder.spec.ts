import { expect, test } from '@playwright/test';

import { signInReadmeLoaded } from '../support/floor';
import { pointKeys } from '../support/devices';

/**
 * UJ-1 step 3 (REL-2, Story 8.6): the reminder. On the first-start stack with the CI mock, the README account presses Send on guide step 2,
 * which 02 left as the current step (or, from a page that has not moved on, upcoming: DW-340). The page then shows the exact prompt as the
 * guide's own message, the reply "The CI mock set the reminder.", one Reminders row "stretch" with its countdown, and the guide's step 2
 * done. The runners' keys are pointed at the CI mock (idempotently: 02 already did) and stay pointed through the steps that follow, where
 * 06 puts them back. Nothing cancels the reminder: it fires during step 4's wait, and the chat and the phone show it there.
 * The guide turn and everything else it made stay in the README session, for example its triage decision (a fallback under the CI
 * mock) and its turn decision with its agent steps; the steps that follow must not depend on their absence.
 * It needs the first-start stack (OCUTALON_URL): without it the group skips as it is declared,
 * before any hook or fixture starts, because a run with no stack may have no browser either (the unit tests' demo-path run in the hosted
 * web job), and a skip inside the test would launch one first.
 */
test.describe('Story 8.6: step 2 of the guide sets a reminder through the chat', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 8.6 needs the first-start stack (OCUTALON_URL), which a run without one lacks');

  test.beforeAll(async () => {
    test.setTimeout(240_000);
    await pointKeys();
  });

  test('the guide prompt gets its reply, the stretch reminder shows with its countdown, and step 2 is done', async ({ page }) => {
    test.setTimeout(120_000);
    const prompt = 'Remind me in 1 minute to stretch.';

    await signInReadmeLoaded(page);
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

    const guide = page.getByRole('region', { name: 'Demo guide' });
    await guide.getByRole('button', { name: /^Step 2, Reminder, (upcoming|current)$/ }).click();
    const shown = guide.locator('.prompt');
    await expect(shown.locator('.prompt-text'), 'step 2 shows its exact prompt').toHaveText(`"${prompt}"`);
    await shown.getByRole('button', { name: 'Send', exact: true }).click();

    const message = page.locator('main app-user-message').filter({ hasText: prompt });
    await expect(message, 'the prompt shows as a message').toHaveCount(1);
    await expect(message.locator('.bubble'), 'which is the exact prompt').toHaveText(prompt);
    await expect(message.locator('.when'), 'with the guide caption').toHaveText(/^From the demo guide/);
    await expect(page.locator('main app-chat-panel').getByText('The CI mock set the reminder.'), 'the reply shows').toHaveCount(1, { timeout: 30_000 });

    const row = page.getByRole('region', { name: 'Status', exact: true }).locator('li.row[data-section="reminders"]');
    await expect(row, 'one reminder shows under Reminders').toHaveCount(1);
    await expect(row.locator('.lead'), 'it is stretch').toHaveText(/^stretch$/i);
    await expect(row.locator('.countdown'), 'with its countdown').toHaveText(/^in \d+ (s|min)$/);
    await expect(guide.getByRole('button', { name: 'Step 2, Reminder, done', exact: true }), 'and the guide marks step 2 done').toHaveCount(1);
  });
});
