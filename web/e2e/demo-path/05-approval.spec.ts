import { expect, test } from '@playwright/test';

import { raise, refOf } from '../support/approvals';
import { dropPhone, phoneMessage } from '../support/devices';
import { CARD_MS, inMs } from '../support/floor';
import { cleanFixtureRows, readApproval, sendNotification } from '../support/iris';
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
    const time = answered.at.slice(11, 16);
    await expect(message.locator('p[data-part="answer"]'), 'the phone says so').toHaveText(`Approved from the simulated phone at ${time}.`, { timeout: CARD_MS });
    await expect(card.locator('p.status'), 'so does the card').toHaveText(`Approved from the simulated phone at ${time}`, { timeout: CARD_MS });
    expect(answered.state, 'the row is approved').toBe('approved');
    expect(answered.channel, 'from the simulated phone').toBe('phone');
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
  }
});

notBuilt('Fixing, then "All 50 orders went through." and Resolved', '11.1');
