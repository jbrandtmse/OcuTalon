import { expect, test, type Page } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { pointKeys, restoreKeys } from '../support/devices';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';
import { composerOf, railOf, replyOf } from '../support/floor';

/**
 * Story 8.6, reminders set and cancelled through the chat, in a real browser against a real stack with the CI mock. The rail user types
 * into the page's composer and presses Send; the real Conversation, Chat, tools and ReminderOps do the rest, and the CI mock scripts
 * the model:
 *   - C1: "Remind me Thursday at 10 to load the new certificate." with the marker reminder-thursday gets the scenario's reply, and a
 *     Reminders row "load the new certificate" shows with a countdown in hours and minutes (the fixed Thursday 2030-11-07);
 *   - C2: the guide prompt sets a reminder that gets the fixed Ref of Test.Schedule.ReminderOpsFixedRef, which the item runs for these
 *     two cases only; "Cancel my reminder to stretch." with the marker reminder-cancel-chat gets the scenario's reply, the row leaves
 *     the rail within one live update without a reload, and the stored reminder is cancelled.
 * beforeAll points the runners' keys at the CI mock and puts the fixed-Ref class behind the ReminderOps item; afterAll puts both back and
 * waits until the runners have recorded their restored keys, because trace/links.spec.ts runs later and expects the no-key reply. Each
 * case removes its reminder and everything the product made for it (ReminderFixture.Remove). The browser runs in UTC with the en-GB
 * locale, the stack's own zone.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const MESSAGES = '/ocutalon/api/v1/messages';
const GUIDE_PROMPT = 'Remind me in 1 minute to stretch.';

/** The text that scenario reminder-thursday sets, whichever case set it and however far that case got. */
const THURSDAY_TEXT = 'load the new certificate';

/** The Ref that scenario reminder-cancel-chat cancels. */
const FIXED_REF = 'zzReminderChatCancel01';

/** How long a reply may take to show after the send: the turn, the live poll and the render. */
const REPLY_MS = 30_000;

/** How long the row of a cancelled reminder may take to leave the rail after the reply. */
const GONE_MS = 15_000;

/** The Refs of the reminders that the running case kept, for the clean-up. */
let kept: string[] = [];

test.beforeAll(async () => {
  test.setTimeout(240_000);
  await pointKeys();
  const lines = await irisScript(
    [
      'Set sc=##class(OcuTalon.Test.Schedule.ReminderOpsFixedRef).Use()',
      'Write !,"CHK|use|",$System.Status.IsOK(sc)',
      'If $System.Status.IsError(sc) Write !,"CHK|why|",$Translate($System.Status.GetErrorText(sc),$Char(13,10)," ")',
    ].join('\n'),
  );
  expect(chk(lines, 'use'), `the fixed-Ref class is behind the ReminderOps item (${lines.join(' ')})`).toBe('1');
});

test.afterAll(async () => {
  test.setTimeout(240_000);
  try {
    const lines = await irisScript(
      [
        'Set sc=##class(OcuTalon.Test.Schedule.ReminderOpsFixedRef).Restore()',
        'Write !,"CHK|restore|",$System.Status.IsOK(sc)',
        'If $System.Status.IsError(sc) Write !,"CHK|why|",$Translate($System.Status.GetErrorText(sc),$Char(13,10)," ")',
      ].join('\n'),
    );
    expect(chk(lines, 'restore'), `the ReminderOps item has its class again (${lines.join(' ')})`).toBe('1');
  } finally {
    try {
      await restoreKeys();
    } finally {
      const lines = await irisScript('Write !,"CHK|records|",##class(OcuTalon.Test.Agent.RunnerFixture).WaitRecords()');
      expect(chk(lines, 'records'), `the runners recorded the restored keys (${lines.join(' ')})`).toBe('1');
    }
  }
});

test.afterEach(async () => {
  const refs = kept;
  kept = [];
  const removes = refs.map((ref) => `Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(${quoted(ref)})`);
  await irisScript(
    [
      ...removes,
      `Set rows=##class(%SQL.Statement).%ExecDirect(,"SELECT Ref FROM OcuTalon_Data.Reminder WHERE Text = ?",${quoted(THURSDAY_TEXT)})`,
      'Set left="" While rows.%Next() { Set left=left_$ListBuild(rows.%Get("Ref")) }',
      'Set at=0 While $ListNext(left,at,ref) { Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(ref) }',
      'Write !,"CHK|removed|1"',
    ].join('\n'),
  );
});

/** Types the text into the composer, presses the main Send button and returns the clientId of the POST /messages that it made. */
async function send(page: Page, text: string): Promise<string> {
  const request = page.waitForRequest((candidate) => candidate.method() === 'POST' && new URL(candidate.url()).pathname === MESSAGES);
  await composerOf(page).fill(text);
  await page.getByRole('main').getByRole('button', { name: 'Send', exact: true }).click();
  return ((await request).postDataJSON() as { clientId: string }).clientId;
}

/** Signs the rail user in and waits for the loaded page. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('RAIL');
  await signIn(page, user, password);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
}

test('C1: a Thursday reminder set through the chat shows in the rail with its countdown', async ({ page }) => {
  test.setTimeout(120_000);
  await open(page);

  const clientId = await send(page, 'Remind me Thursday at 10 to load the new certificate. [[mock:reminder-thursday]]');
  await expect(replyOf(page, clientId), "the scenario's reply shows").toContainText('The CI mock set the Thursday reminder.', { timeout: REPLY_MS });

  const row = railOf(page).locator('li.row[data-section="reminders"]').filter({ hasText: THURSDAY_TEXT });
  await expect(row, 'the reminder shows under Reminders').toHaveCount(1);
  const key = (await row.getAttribute('data-row-key')) ?? '';
  expect(key, "the row's key names the reminder").toMatch(/^reminders:\S+$/);
  kept.push(key.slice('reminders:'.length));
  await expect(row.locator('.lead')).toHaveText(THURSDAY_TEXT);
  await expect(row.locator('.countdown'), 'with its countdown in hours and minutes').toHaveText(/^in \d+ h \d+ min$/);
});

test('C2: a reminder cancelled through the chat leaves the rail within one live update', async ({ page }) => {
  test.setTimeout(120_000);
  kept.push(FIXED_REF);
  await irisScript(
    [
      `Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(${quoted(FIXED_REF)})`,
      `Do ##class(OcuTalon.Test.Schedule.ReminderOpsFixedRef).Next(${quoted(FIXED_REF)})`,
      'Write !,"CHK|next|1"',
    ].join('\n'),
  );
  await open(page);

  const setId = await send(page, GUIDE_PROMPT);
  await expect(replyOf(page, setId), "the guide prompt's reply shows").toContainText('The CI mock set the reminder.', { timeout: REPLY_MS });
  const row = page.locator(`li.row[data-row-key="reminders:${FIXED_REF}"]`);
  await expect(row, 'the reminder with the fixed Ref shows under Reminders').toHaveCount(1);

  const cancelId = await send(page, 'Cancel my reminder to stretch. [[mock:reminder-cancel-chat]]');
  await expect(replyOf(page, cancelId), "the cancel's reply shows").toContainText('The CI mock cancelled the reminder.', { timeout: REPLY_MS });
  await expect(row, 'the row leaves the rail without a reload').toHaveCount(0, { timeout: GONE_MS });

  const lines = await irisScript(
    [`Set r=##class(OcuTalon.Data.Reminder).RefIndexOpen(${quoted(FIXED_REF)})`, 'Write !,"CHK|state|",$Select($IsObject(r):r.State,1:"none")'].join('\n'),
  );
  expect(chk(lines, 'state'), `the stored reminder is cancelled (${lines.join(' ')})`).toBe('cancelled');
});
