import { expect, test } from '@playwright/test';

import { README_ACCOUNT, signInReadme } from '../sign-in/helpers';
import { pointKeys, restoreKeys } from '../support/devices';
import { chk, irisScript, quoted } from '../support/iris';

/**
 * UJ-1 step 3 (REL-2, Story 8.6): the reminder. On the first-start stack with the CI mock, the README account presses Send on guide step 2.
 * The page then shows the exact prompt as the guide's own message, the reply "The CI mock set the reminder.", one Reminders row "stretch"
 * with its countdown, and the guide's step 2 done. The runners' keys point at the CI mock for the test and are put back after it. After
 * it, every pending reminder of the README session (on the first-start stack, only the one it set) is cancelled through the product's
 * cancel path, so that none fires and none shows under Reminders during the steps that follow, and the guide's step 2 is no longer done.
 * The guide turn and everything else it made stay in the README session, for example its triage decision (a fallback under the CI
 * mock), its turn decision with its agent steps, and the cancelled reminder; the steps that follow must not depend on their absence.
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

    await signInReadme(page);
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

    const guide = page.getByRole('region', { name: 'Demo guide' });
    await guide.getByRole('button', { name: 'Step 2, Reminder, upcoming', exact: true }).click();
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

  test.afterAll(async () => {
    test.setTimeout(240_000);
    try {
      const lines = await irisScript(
        [
          `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(README_ACCOUNT.user)},.sc)`,
          'Write !,"CHK|cancelled|",##class(OcuTalon.Test.Schedule.ReminderFixture).CancelPending(s.Ref)',
        ].join('\n'),
      );
      expect(Number(chk(lines, 'cancelled')), `the README session's pending reminder is cancelled (${lines.join(' ')})`).toBeGreaterThanOrEqual(1);
    } finally {
      try {
        await restoreKeys();
      } finally {
        const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
        expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
      }
    }
  });
});
