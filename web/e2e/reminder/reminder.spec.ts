import { expect, test } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { chk, fixtureUser, irisScript, quoted } from '../support/iris';
import { rowOf, unique } from '../support/floor';
import { TRACE_PAGE, drawnMessages, openTrace, signOutTrace } from '../support/trace';

/**
 * Story 8.3, a reminder fires on time on every channel, in a real browser against a real stack. The rail user's session gets a reminder
 * from the product's own set path (Test.Schedule.ReminderFixture.Set submits a SetReminder through Commands.Submit under a bridge
 * context, as the chat's tool does), due in 25 seconds. The page then shows:
 *   - the reminder's row in Reminders, from the real data, with the trace link of its waiter: the link opens Visual Trace on the waiter's
 *     own session, as a trace-role user in a context of its own, and the page draws the start and the timer messages;
 *   - when the reminder is due, within the bound below, the row gone and one notice card `Reminder: <text>.`
 * The bound is generous, because CI asserts order and outcome and never seconds. The test removes the reminder and everything the product
 * made for it (ReminderFixture.Remove). The browser runs in UTC with the en-GB locale, the stack's own zone.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** Seconds from setting the reminder to its due time. */
const DUE_SECONDS = 25;

/** How long the row may take to show after the page has loaded. */
const ROW_MS = 15_000;

/** How long after the due time the card may take: the waiter, the routing, the live poll and the render. */
const CARD_MS = 20_000;

let ref = '';

test.afterEach(async () => {
  if (ref === '') return;
  const removed = ref;
  ref = '';
  await irisScript([`Do ##class(OcuTalon.Test.Schedule.ReminderFixture).Remove(${quoted(removed)})`, 'Write !,"CHK|removed|1"'].join('\n'));
});

test('a reminder shows in the rail with its trace link and fires as a notice card', async ({ page, browser }) => {
  test.setTimeout(90_000);
  const { user, password } = fixtureUser('RAIL');
  const text = unique('reminder');

  const lines = await irisScript(
    [
      `Set s=##class(OcuTalon.Data.Session).ForUser(${quoted(user)},.sc)`,
      `Set j=##class(OcuTalon.Test.Schedule.ReminderFixture).Set(s.Ref,${quoted(text)},${DUE_SECONDS})`,
      'Write !,"CHK|ref|",j.ref',
      'Write !,"CHK|ok|",j.ok',
      'Write !,"CHK|dueAt|",j.dueAt',
      'Write !,"CHK|header|",j.traceHeaderId',
      'Write !,"CHK|alarm|",j.alarmHeaderId',
    ].join('\n'),
  );
  ref = chk(lines, 'ref') ?? '';
  expect(chk(lines, 'ok'), `the reminder is set (${lines.join(' ')})`).toBe('1');
  const dueAt = Date.parse(chk(lines, 'dueAt') ?? '');
  const header = chk(lines, 'header') ?? '';
  const alarm = chk(lines, 'alarm') ?? '';
  expect(header, 'the waiter stored its start header').toMatch(/^\d+$/);
  expect(alarm, 'and set its timer').toMatch(/^\d+$/);

  await signIn(page, user, password);
  const row = rowOf(page, text);
  await expect(row, "the reminder's row shows in Reminders from the real data").toHaveCount(1, { timeout: ROW_MS });
  await expect(row.locator('app-trace-link a'), "its trace link opens its waiter's session").toHaveAttribute('href', TRACE_PAGE + header);

  const context = await browser.newContext({ baseURL: process.env['OCUTALON_URL'], timezoneId: 'UTC', locale: 'en-GB' });
  try {
    const trace = await context.newPage();
    await openTrace(trace, TRACE_PAGE + header, 'LINKS');
    const drawn = await drawnMessages(trace);
    expect(drawn.ids, 'Visual Trace draws the start header').toContain(header);
    expect(drawn.ids, 'and the timer message').toContain(alarm);
  } finally {
    await signOutTrace(context.request);
    await context.close();
  }

  const card = page.locator('main app-notice-card').filter({ hasText: text });
  await expect(row, 'the row leaves when the reminder is due').toHaveCount(0, { timeout: Math.max(dueAt - Date.now(), 0) + CARD_MS });
  await expect(card, 'and one notice card shows').toHaveCount(1, { timeout: CARD_MS });
  await expect(card).toContainText(`Reminder: ${text}.`);
});
