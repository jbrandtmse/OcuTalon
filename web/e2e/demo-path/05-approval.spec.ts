import { expect, test } from '@playwright/test';

import { incidentOf, raise, refOf } from '../support/approvals';
import { dropPhone, phoneMessage } from '../support/devices';
import { CARD_MS, applied, inMs } from '../support/floor';
import { cleanFixtureRows, publishIncident, readApproval, sendNotification } from '../support/iris';
import { clock } from '../support/page';
import { README_ACCOUNT, signInReadme } from '../sign-in/helpers';
import { notBuilt } from './not-built';

// The times of the page's texts are the instance's (UTC on a stack) and the browser's, which the case sets to the same zone and a 24-hour clock.
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/**
 * UJ-1 step 5: the approval. The first test is Approve on the simulated phone on fixtures for Lane A's raise and answer paths (Story 6.3,
 * REL-2), as the README account: a request of an incident and the notice that asks for it are given to the session as IncidentManager
 * will give them; the press on the phone goes through the page to AnswersIn, AnswerOps and Approval.Answer in the production. The phone
 * then reads "Approved from the simulated phone at HH:MM.", the chat's card "Approved from the simulated phone at HH:MM", and the row is
 * approved from the phone. HH:MM is the row's AnsweredAt. The rows and the phone's messages are removed afterwards.
 * The second test is the fix's end on fixtures for Lane A's result path (Story 6.4, REL-2): after the same raise and answer, R is published
 * fixing with A executing (the chip Fixing and "Repairing and resending 50 orders\u2026"), then resolved with A's result (the band "All 50
 * orders went through.", "Recorded in the IRIS audit log." and the chip Resolved), and the `result` notification gives the phone the
 * message "All 50 orders went through.". The real fix (FixExecutor and IncidentManager) waits for Epic 11, below.
 */
test('Approve on the simulated phone, on fixtures: the phone, the card and the row say so', { tag: '@fixtures' }, async ({ page }) => {
  test.setTimeout(120_000);
  const user = README_ACCOUNT.user;
  const rows: string[] = [];
  const start = inMs(-2000);
  try {
    await signInReadme(page);
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    const incident = refOf('D5');
    const request = await raise(page, user, rows, incident, []);
    await sendNotification(user, {
      kind: 'incident',
      catalogKey: 'incident.withFix',
      slots: {
        count: 50,
        itemNoun: { one: 'order', other: 'orders' },
        time: inMs(-120_000),
        cause: 'Data format change',
        fixSummary: 'repair the order date and resend 50 orders',
        field: 'OrderDate',
        before: '10/16/2026',
        after: '2026-10-16',
        resendCount: 50,
      },
      approvalRef: request,
      incidentRef: incident,
    });
    let ref = '';
    await expect.poll(async () => (ref = (await phoneMessage(user, request))?.ref ?? ''), { message: 'the phone has the notice', timeout: CARD_MS }).not.toBe('');
    const message = page.locator(`app-simulated-phone .notification[data-key="${ref}"]`);
    const card = page.locator(`app-chat-panel [data-part="approval"][data-key="${request}"]`);
    await expect(message, 'the simulated phone shows the notice').toHaveCount(1, { timeout: CARD_MS });
    await expect(card, 'and the chat the request card').toHaveCount(1, { timeout: CARD_MS });

    await message.getByRole('button', { name: 'Approve: repair and resend 50 orders', exact: true }).click();
    await expect.poll(async () => readApproval(request).then((one) => one.at), { message: 'the request is answered', timeout: 30_000 }).not.toBe('');
    const answered = await readApproval(request);
    // The phone's line is the server's text (HH:MM); the card writes the page's time, whose en-GB hour has no leading zero before ten.
    const time = answered.at.slice(11, 16);
    await expect(message.locator('p[data-part="answer"]'), 'the phone says so').toHaveText(`Approved from the simulated phone at ${time}.`, { timeout: CARD_MS });
    await expect(card.locator('p.status'), 'so does the card').toHaveText(`Approved from the simulated phone at ${clock(answered.at, 'en-GB', 'UTC')}`, { timeout: CARD_MS });
    expect(answered.state, 'the row is approved').toBe('approved');
    expect(answered.channel, 'from the simulated phone').toBe('phone');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

test('Fixing, then "All 50 orders went through." and Resolved, on fixtures for Lane A\'s result path', { tag: '@fixtures' }, async ({ page }) => {
  test.setTimeout(120_000);
  const user = README_ACCOUNT.user;
  const rows: string[] = [];
  const start = inMs(-2000);
  try {
    await signInReadme(page);
    await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
    const incident = refOf('D5r');
    const request = await raise(page, user, rows, incident, []);
    await sendNotification(user, {
      kind: 'incident',
      catalogKey: 'incident.withFix',
      slots: {
        count: 50,
        itemNoun: { one: 'order', other: 'orders' },
        time: inMs(-120_000),
        cause: 'Data format change',
        fixSummary: 'repair the order date and resend 50 orders',
        field: 'OrderDate',
        before: '10/16/2026',
        after: '2026-10-16',
        resendCount: 50,
      },
      approvalRef: request,
      incidentRef: incident,
    });
    let ref = '';
    await expect.poll(async () => (ref = (await phoneMessage(user, request))?.ref ?? ''), { message: 'the phone has the notice', timeout: CARD_MS }).not.toBe('');
    const message = page.locator(`app-simulated-phone .notification[data-key="${ref}"]`);
    await expect(message, 'the simulated phone shows the notice').toHaveCount(1, { timeout: CARD_MS });
    await message.getByRole('button', { name: 'Approve: repair and resend 50 orders', exact: true }).click();
    await expect.poll(async () => readApproval(request).then((one) => one.at), { message: 'the request is answered', timeout: 30_000 }).not.toBe('');

    const card = page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${incident}"]`);
    await applied(page, await publishIncident(user, incidentOf(incident, [{ ref: request, state: 'executing' }], { state: 'fixing' })));
    await expect(card.locator('.chip-row .chip'), 'the chip says Fixing').toHaveText('Fixing', { timeout: CARD_MS });
    await expect(card.locator('p.fixing'), 'with the fixing line').toHaveText('Repairing and resending 50 orders\u2026');

    const result = { total: 50, resent: 50, completed: 50, failedAgain: 0, skipped: 0, interrupted: 0, reason: '' };
    await applied(page, await publishIncident(user, incidentOf(incident, [{ ref: request, state: 'done', result }], { state: 'resolved' })));
    await expect(card.locator('.chip-row .chip'), 'the chip says Resolved').toHaveText('Resolved', { timeout: CARD_MS });
    const band = card.locator('[data-part="result"]');
    await expect(band.locator('.text'), 'the band says all went through').toHaveText('All 50 orders went through.', { timeout: CARD_MS });
    await expect(card.locator('p.audit'), 'and the audit line follows it').toHaveText('Recorded in the IRIS audit log.');

    await sendNotification(user, {
      kind: 'result',
      catalogKey: 'result.allThrough',
      slots: { count: 50, itemNoun: { one: 'order', other: 'orders' } },
      approvalRef: request,
      incidentRef: incident,
    });
    const phone = page.locator('app-simulated-phone .notification').filter({ hasText: 'All 50 orders went through.' });
    await expect(phone, "the phone shows the result as a message").toHaveCount(1, { timeout: CARD_MS });
    await expect(phone.getByRole('button'), 'with no buttons').toHaveCount(0);
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

notBuilt('Fixing, then "All 50 orders went through." and Resolved, from the real fix (FixExecutor and IncidentManager)', '11.1');
