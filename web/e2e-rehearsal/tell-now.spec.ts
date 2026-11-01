import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { expect, test } from '@playwright/test';

import { ON_MOCK, phoneNotes } from '../e2e/support/demo-path';
import { mailRowsOf, mailboxOf, pointKeys, restoreKeys } from '../e2e/support/devices';
import { CARD_MS, signInReadmeLoaded } from '../e2e/support/floor';
import { chk, irisScript } from '../e2e/support/iris';
import { mark, markWhen } from '../e2e/support/rehearsal';

/** The eval set's item whose expected outcome is Tell now (eval/mail-endpoint-move-tomorrow/case.json): its sender, subject and text. */
interface EvalItem {
  item: { sender: string; subject: string; text: string };
}
const CASE = JSON.parse(readFileSync(join(__dirname, '..', '..', 'eval', 'mail-endpoint-move-tomorrow', 'case.json'), 'utf8')) as EvalItem;

/** The mock's scripted Tell now for a mailbox email (ci/mock/scenarios/B/mail-tell-now.json, matched by this marker in the body). */
const MOCK_MARKER = '[[mock:mail-tell-now]]';

/**
 * The tell-now item of the clean-machine rehearsal (release/rehearse.sh, Story 11.12; FR-1, NFR-8, UX-DR101), once in every run: the eval
 * set's tell-now email goes in through the mailbox's compose form, its subject stamped "Rehearsal run <OCUTALON_REHEARSAL_RUN>: " at the
 * start (the intake cuts "{Sender}: {Subject}" at 80 characters). tellnow_sent is marked right before Send, and tellnow_seen when the chat
 * has a notice card and the phone a message that hold the stamp, or when the item's row shows an outcome other than Tell now. On the mock
 * the marker in the body scripts Tell now; on the real model the outcome is the model's, and another outcome is recorded as an annotation
 * and passes (the rehearsal then has no tell-now sample for the run, and its report says so). The collector reads the decision's own
 * duration from the server. It needs the stack (OCUTALON_URL) and OCUTALON_REHEARSAL_RUN.
 */
test.describe('Story 11.12: the tell-now item', () => {
  test.skip(!process.env['OCUTALON_URL'], 'Story 11.12 needs the first-start stack (OCUTALON_URL), which a run without one lacks');
  test.describe.configure({ mode: 'serial' });

  test.beforeAll(async () => {
    test.setTimeout(240_000);
    if (ON_MOCK) await pointKeys();
  });

  test('tell-now: the item is decided and its notice reaches the chat and the phone', async ({ page }) => {
    test.setTimeout(240_000);
    const run = process.env['OCUTALON_REHEARSAL_RUN'] ?? '';
    expect(run, 'OCUTALON_REHEARSAL_RUN names the run').toMatch(/^[1-9][0-9]*$/);
    const stamp = `Rehearsal run ${run}: `;
    const subject = `${stamp}${CASE.item.subject}`;
    const body = ON_MOCK ? `${CASE.item.text} ${MOCK_MARKER}` : CASE.item.text;

    await signInReadmeLoaded(page);
    const mailbox = await mailboxOf(page);
    await mailbox.getByRole('button', { name: 'Simulate an incoming email', exact: true }).click();
    await mailbox.getByRole('textbox', { name: 'From', exact: true }).fill(CASE.item.sender);
    await mailbox.getByRole('textbox', { name: 'Subject', exact: true }).fill(subject);
    await mailbox.getByRole('textbox', { name: 'Body', exact: true }).fill(body);

    const cards = page.locator('app-chat-panel app-notice-card').filter({ hasText: stamp });
    const messages = phoneNotes(page).filter({ hasText: stamp });
    const chip = mailRowsOf(mailbox, stamp).locator('app-outcome-chip');
    mark('tellnow_sent');
    await mailbox.locator('.form').getByRole('button', { name: 'Send', exact: true }).click();
    await markWhen(
      'tellnow_seen',
      async () => {
        if ((await cards.count()) > 0 && (await messages.count()) > 0) return true;
        const shown = ((await chip.allTextContents())[0] ?? '').trim();
        return shown !== '' && shown !== 'Tell now';
      },
      60_000,
    );

    await expect(chip, 'the item is decided').toHaveText(/\S/, { timeout: 60_000 });
    const outcome = ((await chip.allTextContents())[0] ?? '').trim();
    if (ON_MOCK) expect(outcome, 'the mock decides Tell now').toBe('Tell now');
    if (outcome === 'Tell now') {
      await expect(cards, 'one notice card holds the stamp').toHaveCount(1, { timeout: CARD_MS });
      await expect(cards, 'with the "Why now:" line').toContainText('Why now:');
      await expect(messages, 'and one phone message').toHaveCount(1, { timeout: CARD_MS });
    } else {
      test.info().annotations.push({ type: 'tell-now outcome', description: `the model decided ${outcome}; this run has no tell-now sample` });
    }
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
