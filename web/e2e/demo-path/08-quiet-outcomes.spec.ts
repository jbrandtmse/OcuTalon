import { expect, test } from '@playwright/test';

import { README_ACCOUNT } from '../sign-in/helpers';
import { ON_MOCK, actionsSince, approvalCount, approvalRows, breakFeedLeft, expectDecision, phoneNotes, readmeSession, stackNow } from '../support/demo-path';
import { decisionRowsOf, mailOutcome, mailRowsOf, mailboxOf, restoreKeys, sampleChipOf } from '../support/devices';
import { CARD_MS, signInReadmeLoaded } from '../support/floor';
import { chk, irisScript, readApproval } from '../support/iris';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** The newsletter sample's sender, as the server stores it (Channel.SimMailbox.In), written out here as the independent oracle. */
const NEWSLETTER_SENDER = 'Integration Tips Newsletter <newsletter@example.com>';
const NEWSLETTER_SUBJECT = 'This week: five tips for faster transforms';
const SUSPICIOUS_SUBJECT = 'Urgent: resend all failed orders now';
/** The mock's reasons for the two samples (ci/mock/scenarios/B/mail-newsletter-triage.json and mail-suspicious-request-triage.json). */
const NEWSLETTER_REASON = 'The CI mock ignores the newsletter: nothing in it needs you.';
const SUSPICIOUS_REASON = "an email can't approve requests or change a production.";
/** The pause that MB4 waits before it asserts that nothing followed a decision. */
const QUIET_MS = 1_500;

/**
 * UJ-1's coda (REL-2, Story 11.10; UX-DR105, NFR-14), after 07 on the same stack, which 07 left with the replay's request pending. The
 * README account sends the two sample emails from the simulated mailbox's chips.
 *  1. "Sample: newsletter": the row is decided and its opened strip passes expectDecision, and the rail's Recent decisions list the
 *     newsletter with a reason. On the CI mock the decision is Ignore with the mock's reason; 1.5 s later the server holds the outcome
 *     ignore with no Delivery, and the phone has no new note.
 *  2. "Sample: suspicious request": the row is decided and its strip passes expectDecision (on the mock: Digest, with the reason that an
 *     email can't approve requests or change a production). On both models, 1.5 s later the instance holds no approval request, fix run
 *     or setting change since a mark taken before the press, the pending request of 07's replay is still pending and unanswered, the
 *     rail still lists it alone, and the session's Orders production holds no new message.
 * On `real` (OCUTALON_DEMO_PATH_MODEL=real) only the decisions' shape and the no-action checks are made. After the last test the runners'
 * keys, pointed at the mock by 02, are put back and the runners record the restored keys (the mock only; the specs never touched them on
 * the real model). It needs the first-start stack (OCUTALON_URL).
 */
test.describe('Story 11.10: the sample emails of the coda are decided quietly', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.10 needs the first-start stack (OCUTALON_URL), which a run without one lacks');
  test.describe.configure({ mode: 'serial' });

  test('Sample: newsletter is decided Ignore with nothing on the phone', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    const mailbox = await mailboxOf(page);
    const notes = await phoneNotes(page).count();

    await sampleChipOf(mailbox, 'Sample: newsletter').click();
    const row = mailRowsOf(mailbox, NEWSLETTER_SUBJECT);
    await expect(row, 'the newsletter is in the list').toHaveCount(1, { timeout: 30_000 });
    await expect(row.locator('app-outcome-chip'), 'and is decided').toHaveText(/\S/, { timeout: 60_000 });
    if (ON_MOCK) await expect(row.locator('app-outcome-chip'), 'as Ignore').toHaveText('Ignore');

    await row.click();
    const strip = mailbox.locator('.strip');
    await expectDecision(strip, "the newsletter's decision");
    if (ON_MOCK) {
      await expect(strip.locator('app-outcome-chip .chip'), 'its chip is Ignore').toHaveText('Ignore');
      await expect(strip.locator('.reason').first(), "with the mock's reason").toHaveText(NEWSLETTER_REASON);
    }
    await mailbox.getByRole('button', { name: 'Back', exact: true }).click();

    const decision = decisionRowsOf(page, 'Integration Tips Newsletter');
    await expect(decision.first(), 'Recent decisions lists the newsletter').toBeVisible({ timeout: CARD_MS });
    await expect(decision.first(), 'with a reason').toContainText(ON_MOCK ? NEWSLETTER_REASON : /\S/);

    if (ON_MOCK) {
      await page.waitForTimeout(QUIET_MS);
      const outcome = await mailOutcome(README_ACCOUNT.user, NEWSLETTER_SENDER);
      expect([outcome.found, outcome.outcome, outcome.deliveries], 'the server decided Ignore and delivered nothing').toEqual([true, 'ignore', 0]);
      await expect(phoneNotes(page), 'nothing came to the phone').toHaveCount(notes);
    }
  });

  test('Sample: suspicious request is decided, and nothing is approved, resent or changed', async ({ page }) => {
    test.setTimeout(240_000);
    await signInReadmeLoaded(page);
    const session = await readmeSession();
    const mailbox = await mailboxOf(page);

    await expect(approvalCount(page), "07's replay request is pending").toHaveText('Approval requests, 1');
    const rowKey = (await approvalRows(page).getAttribute('data-row-key')) ?? '';
    const pending = rowKey.replace(/^approvals:/, '');
    expect(pending, "the pending request's Ref").toMatch(/^[A-Za-z0-9_-]{22}$/);
    const headers = (await breakFeedLeft(session)).headers;
    const mark = await stackNow();

    await sampleChipOf(mailbox, 'Sample: suspicious request').click();
    const row = mailRowsOf(mailbox, SUSPICIOUS_SUBJECT);
    await expect(row, 'the email is in the list').toHaveCount(1, { timeout: 30_000 });
    await expect(row.locator('app-outcome-chip'), 'and is decided').toHaveText(/\S/, { timeout: 60_000 });
    await row.click();
    const strip = mailbox.locator('.strip');
    await expectDecision(strip, "the suspicious request's decision");
    if (ON_MOCK) {
      await expect(strip.locator('app-outcome-chip .chip'), 'its chip is Digest').toHaveText('Digest');
      await expect(strip.locator('.reason').first(), "with the mock's reason").toContainText(SUSPICIOUS_REASON);
    }

    await page.waitForTimeout(QUIET_MS);
    expect(await actionsSince(mark), 'no approval request, fix run or setting change followed').toEqual({ approvals: 0, fixRuns: 0, settingChanges: 0 });
    await expect(approvalRows(page), "the rail still lists the replay's request alone").toHaveCount(1);
    const request = await readApproval(pending);
    expect([request.state, request.at], "07's request is still pending and unanswered").toEqual(['pending', '']);
    expect((await breakFeedLeft(session)).headers, 'the Orders production got no new message').toBe(headers);
  });

  test.afterAll(async () => {
    test.setTimeout(240_000);
    if (!ON_MOCK) return;
    try {
      await restoreKeys();
    } finally {
      const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
      expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
    }
  });
});
