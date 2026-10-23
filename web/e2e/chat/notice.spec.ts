import { expect, test, type Locator, type Page } from '@playwright/test';

import { notBuilt } from '../demo-path/not-built';
import { signIn } from '../sign-in/helpers';
import { fixtureUser, seedDecision, seedTurns, sendItem, sendItemDecision, sendNotification } from '../support/iris';
import { fromBottom, plain, scrollListTo, tokenColor } from '../support/page';

/**
 * Story 2.7, the notice cards (N1 to N12; N11 is Story 4.5's), in a real browser against a real stack. Every case signs in as the notice fixture user
 * that test-sign-in.sh created (OCUTALON_NOTICE_USER) and sends items, item decisions and notifications to its own session through
 * the real production (SimMailboxIn and NoticesIn hosts, OutcomeRouter, Notify, WebChatOut), so that nothing here publishes on the
 * README session or the instance stream (api.spec pins their counts) or touches another spec's chat. Each case asserts only on the
 * cards of the texts it made, each with a stamp of its own. The browser runs in UTC with the en-GB locale, which is the stack's own
 * zone (N6 runs in Europe/Berlin), so a time reads the same wherever the specs run.
 *
 * /state's chat holds only the session's newest 100 entries: the cards a case makes are dated now, and N7's turns are dated 2024
 * and 2099, so its order holds on a stack that ran the cases before, in any order of the cases.
 */
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll that a routed /events handler is still answering when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const LIVE_REGIONS = '[aria-live], [role="log"], [role="status"], [role="alert"]';
const EVENTS = '/ocutalon/api/v1/events';

/** The middle dot between the items of a line, with its spaces. */
const DOT = ' \u00B7 ';

/** How long a card may take to reach the page after the send returns: the route, the live poll (1 to 2 s) and the render. */
const CARD_MS = 15_000;

/** The bound of N10 (P30), counted from before the item is sent. */
const FIVE_SECONDS_MS = 5000;

/** The ring strokes that only the bell-ring icon draws; the bell has the clapper and the body alone. */
const BELL_RING = 'path[d="M22 8c0-2.3-.8-4.3-2-6"]';
const BELL_BODY = 'path[d="M10.268 21a2 2 0 0 0 3.464 0"]';

/** A text no other case or run made. */
const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** The card whose text holds the marker. */
const cardOf = (page: Page, marker: string): Locator => page.locator('app-chat-panel app-notice-card').filter({ hasText: marker });

/** Signs the notice user in and waits for the loaded page with its composer. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('NOTICE');
  await signIn(page, user, password);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('textbox', { name: 'Message OcuTalon' })).toBeVisible();
}

/** Counts every focusin of the page from now on, in window.focusins. */
async function countFocusins(page: Page): Promise<void> {
  await page.evaluate(() => {
    const target = window as unknown as { focusins?: number };
    target.focusins = 0;
    document.addEventListener('focusin', () => {
      target.focusins = (target.focusins ?? 0) + 1;
    });
  });
}

/** Today's date with the time given, as a UTC ISO time. */
const today = (time: string): string => `${new Date().toISOString().slice(0, 10)}T${time}Z`;

/** N1: a tell-now card: the attention bar, bell-ring, the summary, the Why now line, no heading and a strip of line 1 and Details. */
test('N1: a tell-now notice shows as a card with its Why now line and the strip', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  await countFocusins(page);
  const summary = unique('N1');
  const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary, reasons: 'zz first.\nzz second.', confidence: 0.9, costUSD: 0.0003 });
  await sendItemDecision(user, { outcome: 'tellnow', summary, decisionRef });
  const card = cardOf(page, summary);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });

  const notice = card.locator('.notice');
  await expect(notice, 'the accent bar is 4px').toHaveCSS('border-left-width', '4px');
  await expect(notice, 'in the attention colour').toHaveCSS('border-left-color', await tokenColor(page, '--attention'));
  const icon = card.locator('.notice > app-icon');
  await expect(icon.locator('svg[aria-hidden="true"]'), 'the icon is hidden from assistive technology').toHaveCount(1);
  await expect(icon.locator(BELL_RING), 'and is the bell-ring').toHaveCount(1);
  await expect(icon, 'in the attention ink').toHaveCSS('color', await tokenColor(page, '--attention-ink'));
  await expect(card.locator('.text'), 'the summary is the text').toHaveText(summary);
  await expect(card.locator('.why'), 'then the Why now line, the first reason').toHaveText('Why now: zz first.');
  await expect(card.getByRole('heading'), 'a card has no heading').toHaveCount(0);
  await expect(card.locator('h1, h2, h3, h4, h5, h6, .title'), 'and no title').toHaveCount(0);

  const strip = card.locator('app-decision-strip');
  await expect(strip).toHaveCount(1);
  await expect(strip.locator('app-outcome-chip .chip'), 'line 1 of the strip: the outcome').toHaveText('Tell now');
  await expect(strip.locator('.line1 .meta'), 'the confidence and the decision\'s own cost').toHaveText(`Confidence 0.90${DOT}$0.0003`);
  await expect(strip.getByRole('button', { name: 'Decision details' }), 'with Details').toHaveCount(1);
  await expect(strip.locator('.reason'), 'and no reason lines: the Why now line says why').toHaveCount(0);
  await expect(card.locator(LIVE_REGIONS), 'nothing in the card is a live region').toHaveCount(0);
  expect(await card.evaluate((el, selector) => el.closest(selector) !== null, LIVE_REGIONS), 'and it is in none').toBe(false);
  expect(await page.evaluate(() => (window as unknown as { focusins?: number }).focusins), 'no focus moved when the card landed').toBe(0);
});

/** N2: a notice written by code keeps its own two lines, with the key's own Why now line. */
test('N2: a code-written notice keeps its own two lines', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const production = `Orders${Date.now().toString(36)}`;
  await sendItemDecision(user, {
    outcome: 'tellnow',
    summary: unique('N2'),
    catalogKey: 'watch.productionStopped',
    slots: { production, time: new Date().toISOString().slice(0, 19) + 'Z' },
  });
  const card = cardOf(page, production);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('.text'), 'the first line is the key\'s text, with its time').toHaveText(new RegExp(`^The ${production} production stopped at \\d\\d:\\d\\d\\.$`));
  await expect(card.locator('.why'), 'the second line is its own Why now line').toHaveText(`Why now: you asked me to watch the ${production} production.`);
  await expect(card.locator('.notice'), 'a tell-now card').toHaveCSS('border-left-color', await tokenColor(page, '--attention'));
  expect(plain(await card.locator('.body').innerText()).includes('Why now:'), 'the card says why now once').toBe(true);
});

/** N3: only Tell now and Act notify: an ignore and a digest show nothing, an act shows its card with the chip Act, also after a reload. */
test('N3: only Tell now and Act notify', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const ignored = unique('N3 ignore');
  const digested = unique('N3 digest');
  const acted = unique('N3 act');
  const reasons = 'zz reason.';
  const ignoreRef = await seedDecision(user, { outcome: 'ignore', summary: ignored, reasons, confidence: 0.8, costUSD: 0.0003 });
  const digestRef = await seedDecision(user, { outcome: 'digest', summary: digested, reasons, confidence: 0.8, costUSD: 0.0003 });
  const actRef = await seedDecision(user, { outcome: 'act', summary: acted, reasons, confidence: 0.95, costUSD: 0.0003 });
  await sendItemDecision(user, { outcome: 'ignore', summary: ignored, decisionRef: ignoreRef });
  await sendItemDecision(user, { outcome: 'digest', summary: digested, decisionRef: digestRef });
  await sendItemDecision(user, { outcome: 'act', summary: acted, decisionRef: actRef });
  const card = cardOf(page, acted);
  await expect(card, 'the act shows its card').toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('app-decision-strip app-outcome-chip .chip'), 'with the chip Act').toHaveText('Act');
  await expect(card.locator('.why'), 'and the first reason as its Why now line').toHaveText('Why now: zz reason.');
  await expect(cardOf(page, ignored), 'the ignore shows nothing').toHaveCount(0);
  await expect(cardOf(page, digested), 'nor does the digest').toHaveCount(0);
  await expect(page.getByText(ignored), 'nowhere on the page').toHaveCount(0);

  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(card, 'after a reload the act card is still there').toHaveCount(1);
  await expect(card.locator('app-decision-strip app-outcome-chip .chip')).toHaveText('Act');
  await expect(page.getByText(ignored), 'and the ignore and the digest are still not').toHaveCount(0);
  await expect(page.getByText(digested)).toHaveCount(0);
});

/** N4: a fallback with no decision row shows Tell now and the Fallback flag, and no confidence, no cost and no Details. */
test('N4: a fallback with no decision shows Tell now and the Fallback flag', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const summary = unique('N4');
  await sendItemDecision(user, { outcome: 'tellnow', summary, fallback: true, fallbackReason: 'refusal' });
  const card = cardOf(page, summary);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('.text')).toHaveText(summary);
  await expect(card.locator('.why'), 'the reason is the first line').toHaveText('Why now: the model declined to answer');
  const strip = card.locator('app-decision-strip');
  await expect(strip.locator('app-outcome-chip .chip'), 'the chip is Tell now').toHaveText('Tell now');
  await expect(strip.locator('app-fallback-flag'), 'with the Fallback flag').toHaveCount(1);
  await expect(strip.getByText('Confidence'), 'no confidence').toHaveCount(0);
  await expect(strip.locator('.meta'), 'and no cost').toHaveCount(0);
  expect(plain(await card.innerText()).includes('$'), 'no dollar sign anywhere in the card').toBe(false);
  await expect(strip.getByRole('button', { name: 'Decision details' }), 'no Details').toHaveCount(0);
});

/** N5: a reminder card: the bell, the info bar, the text, and its due and arrival times. A reminder with no due time has no caption. */
test('N5: a reminder card shows its due and arrival times', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const text = unique('N5').replace(/^zz /, 'stretch ');
  await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text, dueAt: today('12:00:00') } });
  const card = cardOf(page, text);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  const icon = card.locator('.notice > app-icon');
  await expect(icon.locator(BELL_BODY), 'the icon is the bell').toHaveCount(1);
  await expect(icon.locator(BELL_RING), 'with no ring strokes').toHaveCount(0);
  await expect(icon, 'in the info ink').toHaveCSS('color', await tokenColor(page, '--info-ink'));
  await expect(card.locator('.notice'), 'the accent bar is 4px').toHaveCSS('border-left-width', '4px');
  await expect(card.locator('.notice'), 'in the info ink').toHaveCSS('border-left-color', await tokenColor(page, '--info-ink'));
  await expect(card.locator('.text'), 'the text is the catalog\'s').toHaveText(`Reminder: ${text}.`);
  await expect(card.locator('.caption'), 'the due time, then when the card arrived').toHaveText(new RegExp(`^Due 12:00${DOT}arrived \\d{1,2}:\\d\\d$`));
  await expect(card.locator('.why'), 'a reminder has no Why now line').toHaveCount(0);
  await expect(card.locator('app-decision-strip'), 'and no strip').toHaveCount(0);

  const bare = unique('N5').replace(/^zz /, 'no due ');
  await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text: bare } });
  const none = cardOf(page, bare);
  await expect(none).toHaveCount(1, { timeout: CARD_MS });
  await expect(none.locator('.caption'), 'a reminder with no due time has no caption').toHaveCount(0);
});

/** N6: in another zone than the instance's the times name the browser's zone (UX-DR123): Berlin in July is CEST. */
test.describe('N6: another zone', () => {
  test.use({ timezoneId: 'Europe/Berlin', locale: 'en-GB' });

  test('N6: page times beside message text name the browser\'s zone when it differs', async ({ page }) => {
    const { user } = fixtureUser('NOTICE');
    await open(page);
    const text = unique('N6').replace(/^zz /, 'stretch ');
    await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text, dueAt: '2026-07-15T12:00:00Z' } });
    const card = cardOf(page, text);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.caption'), '12:00 UTC is 14:00 CEST; the arrival is in CEST in summer and CET in winter').toHaveText(new RegExp(`^Due 14:00 CEST${DOT}arrived \\d{1,2}:\\d\\d CES?T$`));
  });
});

/** N7: a reload keeps the cards in the conversation, in time order (DW-62): a turn of 2024, the card, a turn of 2099. */
test('N7: a reload keeps the cards in the conversation in time order', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  const seeded = await seedTurns(user, [
    { createdAt: '2024-01-01T10:00:00Z', text: unique('N7 early'), replyText: 'An early reply.' },
    { createdAt: '2099-01-01T10:00:00Z', text: unique('N7 late'), replyText: 'A late reply.' },
  ]);
  await open(page);
  const [early, late] = seeded.refs as [string, string];
  const summary = unique('N7');
  await sendItemDecision(user, { outcome: 'tellnow', summary, fallback: true, fallbackReason: 'timeout' });
  const card = cardOf(page, summary);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });

  /** The three entries in the order the list shows them, such as early,card,late; "missing" when the list lacks one. */
  const order = (): Promise<string> =>
    page.evaluate(
      ({ first, last, marker }) => {
        const entries = Array.from(document.querySelectorAll('app-chat-panel .entries > *'));
        const found: Array<[string, number]> = [
          ['early', entries.findIndex((el) => el.querySelector(`[data-part="user"][data-key="${first}"]`) !== null)],
          ['card', entries.findIndex((el) => el.matches('app-notice-card') && (el.textContent ?? '').includes(marker))],
          ['late', entries.findIndex((el) => el.querySelector(`[data-part="user"][data-key="${last}"]`) !== null)],
        ];
        return found.some(([, at]) => at < 0)
          ? 'missing'
          : found
              .sort((x, y) => x[1] - y[1])
              .map(([name]) => name)
              .join(',');
      },
      { first: early, last: late, marker: summary },
    );
  expect(await order(), 'a card that arrives live comes after the turns the snapshot held').toBe('early,late,card');
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(card).toHaveCount(1);
  expect(await order(), 'after a reload the snapshot merges it by time: the turn of 2024, the card, the turn of 2099').toBe('early,card,late');
});

/** N8: /events serves WebChatOut's notification with the card's fields. */
test('N8: /events serves the notification with the card\'s fields', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const cursor = Number(await page.locator('main.main').getAttribute('data-session-seq'));
  expect(Number.isInteger(cursor)).toBe(true);
  const summary = unique('N8');
  const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary, reasons: 'zz first.\nzz second.', confidence: 0.9, costUSD: 0.0003 });
  await sendItemDecision(user, { outcome: 'tellnow', summary, decisionRef });
  type Served = { type: string; payload: Record<string, unknown> & { decision?: Record<string, unknown> } };
  let served: Served | undefined;
  await expect
    .poll(
      async () => {
        const response = await page.request.get(`${EVENTS}?after=${cursor}&afterInstance=0`);
        const body = (await response.json()) as { events: Served[] };
        served = body.events.find((event) => event.type === 'notification' && event.payload['text'] === summary);
        return served !== undefined;
      },
      { message: 'the notification event is served', timeout: CARD_MS },
    )
    .toBe(true);
  const payload = served!.payload;
  expect(String(payload['ref']), 'ref is the card\'s Ref').toMatch(/^[A-Za-z0-9_-]{22}$/);
  expect([payload['kind'], payload['text'], payload['whyNow'], payload['decisionRef']], 'the card\'s fields').toEqual(['tellnow', summary, 'Why now: zz first.', decisionRef]);
  expect(String(payload['createdAt']), 'createdAt is a UTC time').toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
  expect(payload['fallbackReason'], 'a decision that was not a fallback has no fallback reason').toBeUndefined();
  expect([payload.decision?.['ref'], payload.decision?.['outcome'], payload.decision?.['reasons'], payload.decision?.['costUSD']], 'with the decision embedded').toEqual([decisionRef, 'tellnow', 'zz first.\nzz second.', 0.0003]);
});

/** N9: markup in an arriving item shows as text. */
test('N9: markup in an arriving item shows as text', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const sender = unique('N9');
  await sendItem(user, { sender, subject: '<i>zz</i>', text: 'zz body' });
  const card = cardOf(page, sender);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('.text'), 'the subject is shown literally').toHaveText(`${sender}: <i>zz</i>`);
  await expect(card.locator('i'), 'and no element was made of it').toHaveCount(0);
});

/**
 * N10: an untrusted item reaches the web chat as a tell-now card within 5 seconds (P30). The item goes to the real Intake from a
 * SimMailboxIn host; the stack's Decide gives the fallback, so the card says why now and carries the Fallback flag. The clock
 * starts before the send, and the elapsed time is logged.
 */
test('N10: an untrusted item reaches the web chat as a tell-now card within 5 seconds', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const sender = unique('N10');
  const started = Date.now();
  await sendItem(user, { sender, subject: 'Invoice', text: 'zz body [[mock:refusal]]' });
  const card = cardOf(page, sender);
  const seen = await card.waitFor({ state: 'attached', timeout: Math.max(1, FIVE_SECONDS_MS - (Date.now() - started)) }).then(
    () => true,
    () => false,
  );
  const elapsed = Date.now() - started;
  console.log(`N10: the untrusted item ${seen ? 'became' : 'did not become'} a tell-now card in ${elapsed} ms, counted from before the send`);
  expect(seen, 'the card is in the web chat within 5 s, counted from before the send').toBe(true);
  expect(elapsed, 'in under 5000 ms').toBeLessThan(FIVE_SECONDS_MS);
  await expect(card.locator('.text')).toHaveText(`${sender}: Invoice`);
  await expect(card.locator('.why'), 'with a Why now line').toHaveText(/^Why now: .+/);
  await expect(card.locator('app-decision-strip app-fallback-flag'), 'and the Fallback flag').toHaveCount(1);
});

/**
 * N12: scrolled up, a card that lands changes nothing about the list and moves no focus; New messages shows, and pressing it takes
 * the list to the bottom and focuses the card (the way a reply that lands does, C9).
 */
test('N12: scrolled up, a card that lands shows New messages and the press focuses it', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  const stamp = Date.now().toString(36);
  await seedTurns(
    user,
    Array.from({ length: 30 }, (_unused, i) => ({
      createdAt: `2020-01-01T10:${String(10 + i).padStart(2, '0')}:00Z`,
      text: `zz N12 ${stamp} message ${i}`,
      replyText: `Reply ${i} to message ${i}.\nIt has a second line so that the list is tall.`,
    })),
  );
  await open(page);
  const list = page.locator('app-chat-panel > .list');
  await expect.poll(() => fromBottom(list), { message: 'the list starts at the bottom' }).toBeLessThanOrEqual(24);
  await scrollListTo(list, 'top');
  const button = page.getByRole('button', { name: 'New messages' });
  await expect(button, 'nothing new yet').toHaveCount(0);

  const summary = unique('N12');
  await sendItemDecision(user, { outcome: 'tellnow', summary, fallback: true, fallbackReason: 'timeout' });
  const card = cardOf(page, summary);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(button, 'the card that landed while the list is scrolled up shows New messages').toBeVisible();
  expect(await list.evaluate((el) => el.scrollTop), 'the list did not move').toBe(0);
  expect(await page.evaluate(() => document.activeElement === document.body), 'and no focus moved when the card landed').toBe(true);

  await button.click();
  await expect.poll(() => fromBottom(list), { message: 'pressing it puts the list at the bottom' }).toBeLessThanOrEqual(24);
  await expect(card.locator('.notice'), 'and focuses the card').toBeFocused();
  await expect(button, 'and the button is gone').toHaveCount(0);
});

notBuilt('a tell-now notification reaches the simulated phone within 5 seconds', '4.5');
