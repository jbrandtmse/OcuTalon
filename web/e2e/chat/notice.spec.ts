import { expect, test, type Locator, type Page } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { loadedAfter } from '../support/floor';
import { cleanFixtureRows, fixtureUser, seedDecision, seedIncident, seedTurns, sendItem, sendItemDecision, sendNotification } from '../support/iris';
import { countFocusins, fromBottom, plain, scrollListTo, tokenColor } from '../support/page';

/**
 * Story 2.7, the notice cards (N1 to N21; N16 is Story 17.10's digest card, completed by Story 18.4, which adds N17 to N19: Got it and the phone's digest; N11, the simulated phone's half of N10, is Story 4.5's), in a real browser against a real stack. Every case signs in as the notice fixture user
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
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('textbox', { name: 'Message OcuTalon' })).toBeVisible();
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
  expect(plain(await card.locator('.body').innerText()).split('Why now:').length - 1, 'the card says why now once').toBe(1);
});

/** N3: only Tell now and Act notify: an ignore and a digest show nothing, an act shows its card with the chip Act and no Got it (on the phone too), also after a reload. */
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
  await expect(card.getByRole('button', { name: 'Got it', exact: true }), 'and no Got it: it marks tell-now decisions only (AD-14)').toHaveCount(0);
  const actMessage = messageOf(page, acted);
  await expect(actMessage, 'the act reaches the phone').toHaveCount(1, { timeout: CARD_MS });
  await expect(actMessage.getByRole('button', { name: 'Got it', exact: true }), 'with no Got it either').toHaveCount(0);
  await expect(cardOf(page, ignored), 'the ignore shows nothing').toHaveCount(0);
  await expect(cardOf(page, digested), 'nor does the digest').toHaveCount(0);
  // The status rail lists every attention decision of the session, an ignored one too, so these absence checks look in the chat.
  await expect(page.getByRole('main').getByText(ignored), 'nowhere in the chat').toHaveCount(0);

  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(card, 'after a reload the act card is still there').toHaveCount(1);
  await expect(card.locator('app-decision-strip app-outcome-chip .chip')).toHaveText('Act');
  await expect(page.getByRole('main').getByText(ignored), 'and the ignore and the digest are still not').toHaveCount(0);
  await expect(page.getByRole('main').getByText(digested)).toHaveCount(0);
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

/**
 * N9: markup in an arriving item shows as text. Like N10, the item's text carries the mock's refusal marker, which stays inert on a
 * keyless stack: the real Decide's precheck answers no_key before anything is sent, so the item becomes a tell-now fallback card.
 */
test('N9: markup in an arriving item shows as text', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const sender = unique('N9');
  await sendItem(user, { sender, subject: '<i>zz</i>', text: 'zz body [[mock:refusal]]' });
  const card = cardOf(page, sender);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('.text'), 'the subject is shown literally').toHaveText(`${sender}: <i>zz</i>`);
  await expect(card.locator('i'), 'and no element was made of it').toHaveCount(0);
});

/**
 * N10: an untrusted item reaches the web chat as a tell-now card within 5 seconds (P30). The item goes to the real Intake from a
 * SimMailboxIn host; the stack has no model key, so the real Decide's precheck answers no_key before anything is sent (the refusal
 * marker stays inert), and the card says why now in the words of that reason and carries the Fallback flag. The clock starts
 * before the send, and the elapsed time is logged.
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
  await expect(card.locator('.why'), 'with the Why now line of the no-key fallback').toHaveText('Why now: no model key is set');
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

/** The colours that a card paints and those that its tokens give in the colour scheme the page is in now (a probe element reads the tokens). */
async function paintOf(card: Locator): Promise<{ background: string; bar: string; ink: string; tokenBackground: string; tokenBar: string; tokenInk: string }> {
  return card.evaluate((el) => {
    const notice = el.querySelector('.notice') as HTMLElement;
    const tellNow = notice.classList.contains('tell-now');
    const probe = document.createElement('div');
    probe.style.background = 'var(--notice-card-background)';
    probe.style.borderInlineStart = `var(${tellNow ? '--notice-card-accent-bar-tell-now' : '--notice-card-accent-bar'})`;
    probe.style.borderInlineStartStyle = 'solid';
    probe.style.color = `var(${tellNow ? '--attention-ink' : '--info-ink'})`;
    document.body.append(probe);
    const token = getComputedStyle(probe);
    const shown = getComputedStyle(notice);
    const result = {
      background: shown.backgroundColor,
      bar: shown.borderInlineStartColor,
      ink: getComputedStyle(notice.querySelector('app-icon') as HTMLElement).color,
      tokenBackground: token.backgroundColor,
      tokenBar: token.borderInlineStartColor,
      tokenInk: token.color,
    };
    probe.remove();
    return result;
  });
}

/**
 * N13: both kinds of card take the colour scheme's tokens, in the light scheme and in the dark one (UX-DR69): the card's
 * background, its accent bar and its icon ink are the scheme's own notice-card, attention and info tokens, and the dark values
 * differ from the light ones, so a colour written into the card instead of a token fails in one of the two.
 */
test('N13: the cards take the tokens of the light and the dark scheme', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await page.emulateMedia({ colorScheme: 'light' });
  await open(page);
  const summary = unique('N13');
  await sendItemDecision(user, { outcome: 'tellnow', summary, fallback: true, fallbackReason: 'refusal' });
  const text = unique('N13').replace(/^zz /, 'stretch ');
  await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text, dueAt: today('12:00:00') } });
  const tellNow = cardOf(page, summary);
  const reminder = cardOf(page, text);
  await expect(tellNow).toHaveCount(1, { timeout: CARD_MS });
  await expect(reminder).toHaveCount(1, { timeout: CARD_MS });

  const light = { tellNow: await paintOf(tellNow), reminder: await paintOf(reminder) };
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(page.locator('body'), 'the page is in its dark scheme').toHaveCSS('background-color', 'rgb(17, 25, 43)');
  const dark = { tellNow: await paintOf(tellNow), reminder: await paintOf(reminder) };
  for (const [scheme, paints] of [['light', light], ['dark', dark]] as const) {
    for (const [kind, paint] of [['tell-now', paints.tellNow], ['reminder', paints.reminder]] as const) {
      expect(paint.background, `${scheme} ${kind} card: the background is the notice-card background`).toBe(paint.tokenBackground);
      expect(paint.bar, `${scheme} ${kind} card: the accent bar is the kind's bar token`).toBe(paint.tokenBar);
      expect(paint.ink, `${scheme} ${kind} card: the icon is in the kind's ink`).toBe(paint.tokenInk);
    }
  }
  expect(dark.tellNow.tokenBackground, 'the dark card background is not the light one').not.toBe(light.tellNow.tokenBackground);
  expect(dark.tellNow.tokenBar, 'the dark attention bar is not the light one').not.toBe(light.tellNow.tokenBar);
  expect(dark.reminder.tokenBar, 'the dark info bar is not the light one').not.toBe(light.reminder.tokenBar);
  expect(dark.tellNow.tokenInk, 'the dark attention ink is not the light one').not.toBe(light.tellNow.tokenInk);
});

/**
 * N14: a reload draws a card as it was sent (DW-62): a fallback card keeps its Fallback flag and its words, and a reminder card
 * keeps its due time, so its caption reads the same.
 */
test('N14: a reload keeps a fallback card\'s flag and a reminder card\'s due time', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const summary = unique('N14');
  await sendItemDecision(user, { outcome: 'tellnow', summary, fallback: true, fallbackReason: 'refusal' });
  const text = unique('N14').replace(/^zz /, 'stretch ');
  await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text, dueAt: today('12:00:00') } });
  const tellNow = cardOf(page, summary);
  const reminder = cardOf(page, text);
  await expect(tellNow).toHaveCount(1, { timeout: CARD_MS });
  await expect(reminder).toHaveCount(1, { timeout: CARD_MS });
  const caption = await reminder.locator('.caption').innerText();
  expect(plain(caption), 'the caption before the reload').toMatch(new RegExp(`^Due 12:00${DOT}arrived \\d{1,2}:\\d\\d$`));

  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(tellNow, 'the fallback card is still there').toHaveCount(1);
  await expect(tellNow.locator('.why'), 'with the words of its reason').toHaveText('Why now: the model declined to answer');
  await expect(tellNow.locator('app-decision-strip app-outcome-chip .chip'), 'the chip Tell now').toHaveText('Tell now');
  await expect(tellNow.locator('app-decision-strip app-fallback-flag'), 'and the Fallback flag').toHaveCount(1);
  await expect(tellNow.getByRole('button', { name: 'Decision details' }), 'with no Details').toHaveCount(0);
  await expect(reminder, 'the reminder card is still there').toHaveCount(1);
  await expect(reminder.locator('.text')).toHaveText(`Reminder: ${text}.`);
  await expect(reminder.locator('.caption'), 'with the due time, and the arrival time it had').toHaveText(caption);
});

/**
 * N15: hostile text in a card stays text and stays inside it: markup in the summary and in the first reason shows literally, and
 * a word too long to break (the reason's, which has no length limit; an ItemDecision's summary holds 80 characters) does not widen
 * the card, the list or the page.
 */
test('N15: markup and an unbroken word in a card stay text inside the card', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const stamp = unique('N15');
  const summary = `${stamp} <b>bold</b> ${'W'.repeat(30)}`;
  const reason = `zz <u>first</u> ${'R'.repeat(120)}.`;
  const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary: stamp, reasons: reason, confidence: 0.9, costUSD: 0.0003 });
  await sendItemDecision(user, { outcome: 'tellnow', summary, decisionRef });
  const card = cardOf(page, stamp);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(card.locator('.text'), 'the summary is shown literally').toHaveText(summary);
  await expect(card.locator('.why'), 'and so is the first reason').toHaveText(`Why now: ${reason}`);
  await expect(card.locator('b, u'), 'no element was made of either').toHaveCount(0);
  const fits = await card.evaluate((el) => {
    const notice = el.querySelector('.notice') as HTMLElement;
    const list = el.closest('.list') as HTMLElement;
    return { notice: notice.scrollWidth <= notice.clientWidth, list: list.scrollWidth <= list.clientWidth, page: document.documentElement.scrollWidth <= document.documentElement.clientWidth };
  });
  expect(fits, 'the unbroken words wrap: the card, the list and the page have no sideways scroll').toEqual({ notice: true, list: true, page: true });
});

/** The strokes that only the inbox icon draws. */
const INBOX = 'polyline[points="22 12 16 12 14 15 10 15 8 12 2 12"]';

/** The width and colour that a border token such as --digest-card-accent-bar ("4px #399897") gives a left border, as the browser computes them. */
function barOf(page: Page, token: string): Promise<{ width: string; color: string }> {
  return page.evaluate((name) => {
    const probe = document.createElement('span');
    probe.style.borderLeft = `var(${name})`;
    probe.style.borderLeftStyle = 'solid';
    document.body.append(probe);
    const style = getComputedStyle(probe);
    const bar = { width: style.borderLeftWidth, color: style.borderLeftColor };
    probe.remove();
    return bar;
  }, token);
}

/** The simulated phone of the page (the stack is in demo mode). */
const phoneOf = (page: Page): Locator => page.getByRole('region', { name: 'Simulated devices' }).locator('app-simulated-phone');

/** The phone message whose text holds the marker. */
const messageOf = (page: Page, marker: string): Locator => phoneOf(page).locator('.notification').filter({ hasText: marker });

/** The line that a handled notice ends with, in the browser's zone (UTC here): "Marked as handled at 14:12". */
const HANDLED = /^Marked as handled at \d{1,2}:\d{2}/;

/**
 * N16 (DW-874, Story 17.10; the full card is Story 18.4's): a digest Notification through Notify is a digest card: the digest card's surface, the 4px
 * brand-teal accent bar (--digest-card-accent-bar), the inbox icon in the info ink and the catalog's pieces one on each line, with no heading, title, strip,
 * caption or Why now line; then "What I checked (n)" with aria-expanded over the check rows, expanded when a row failed or was not checked and collapsed when
 * all passed, and a press opens and closes it. After a reload the snapshot shows the same cards.
 */
test('N16: a digest shows as a digest card with its text and a What I checked disclosure, also after a reload', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const marker = unique('N16');
  const calm = unique('N16calm');
  const failedEntry = `${marker} Orders service`;
  const parts = (summary: string): unknown[] => [
    { key: 'digest.greetingEvening', slots: {} },
    { key: 'digest.checkedQuiet', slots: { checked: 'the Chat agent' } },
    { key: 'checks.allPassed', slots: {} },
    { key: 'digest.saved', slots: { count: 1, summary } },
    { key: 'digest.cost', slots: { cost: 0.042 } },
  ];
  const lines = [{ key: 'digest.notCheckedSizeLimit', slots: { entry: 'the Billing database' } }];
  const expected = (summary: string): string[] => [
    'Good evening.',
    'I checked the Chat agent (all running, no errors, no backlog).',
    'Everything I checked passed.',
    "Not checked: the Billing database (OcuTalon can't read this database's size limit).",
    `Saved for later (1): ${summary}`,
    "Yesterday's cost: $0.04.",
  ];
  const rows = [
    { result: 'failed', entry: failedEntry, finding: 'It has not answered since 02:10.', checkedAt: today('02:10:00') },
    { result: 'passed', entry: 'the Chat agent', finding: '', checkedAt: today('02:11:00') },
  ];
  const calmRows = [
    { result: 'passed', entry: 'the Chat agent', finding: '', checkedAt: today('02:10:00') },
    { result: 'passed', entry: 'the Billing database', finding: '', checkedAt: today('02:11:00') },
  ];
  await sendNotification(user, { kind: 'digest', catalogKey: 'checks.allPassed', slots: { parts: parts(marker), lines, rows } });
  await sendNotification(user, { kind: 'digest', catalogKey: 'checks.allPassed', slots: { parts: parts(calm), lines, rows: calmRows } });
  const card = cardOf(page, marker);
  const calmCard = cardOf(page, calm);

  /** Every leg of the cards, before and after the reload. */
  const assertCards = async (when: string): Promise<void> => {
    await expect(card, `${when}: one card`).toHaveCount(1);
    await expect(card.locator('.notice.digest'), `${when}: of the class digest`).toHaveCount(1);
    await expect(card.locator(`.notice > app-icon ${INBOX}`), `${when}: the icon is the inbox`).toHaveCount(1);
    await expect(card.locator('.notice > app-icon'), `${when}: in the info ink`).toHaveCSS('color', await tokenColor(page, '--info-ink'));
    const bar = await barOf(page, '--digest-card-accent-bar');
    await expect(card.locator('.notice'), `${when}: the accent bar is 4px`).toHaveCSS('border-left-width', '4px');
    expect(bar.width, `${when}: the token's width is 4px`).toBe('4px');
    await expect(card.locator('.notice'), `${when}: in the digest card's brand-teal`).toHaveCSS('border-left-color', bar.color);
    await expect(card.locator('.notice'), `${when}: on the digest card's surface`).toHaveCSS('background-color', await tokenColor(page, '--digest-card-background'));
    const shown = (await card.locator('.text').innerText()).split('\n');
    expect(shown, `${when}: the text keeps its line breaks, one piece on each line`).toEqual(expected(marker));
    await expect(card.locator('h1, h2, h3, h4, h5, h6, [role="heading"], .title'), `${when}: no heading or title`).toHaveCount(0);
    await expect(card.locator('app-decision-strip, .caption, .why'), `${when}: no strip, caption or Why now line`).toHaveCount(0);

    const checked = card.getByRole('button', { name: 'What I checked (2)', exact: true });
    await expect(checked, `${when}: the disclosure names the count`).toHaveCount(1);
    await expect(checked, `${when}: a failed row expands it`).toHaveAttribute('aria-expanded', 'true');
    const checkRows = card.locator('app-check-rows .row');
    await expect(checkRows, `${when}: two check rows`).toHaveCount(2);
    await expect(checkRows.nth(0).locator('.word'), `${when}: the failed row first`).toHaveText('Failed');
    await expect(checkRows.nth(0).locator('.entry'), `${when}: with its entry`).toHaveText(failedEntry);
    await expect(checkRows.nth(0).locator('.finding'), `${when}: and its finding`).toHaveText('It has not answered since 02:10.');
    await expect(checkRows.nth(1).locator('.word'), `${when}: the passed row second`).toHaveText('Passed');
    await expect(checkRows.nth(0), `${when}: the rows show`).toBeVisible();

    await expect(calmCard, `${when}: one calm card`).toHaveCount(1);
    const calmButton = calmCard.getByRole('button', { name: 'What I checked (2)', exact: true });
    await expect(calmButton, `${when}: all passed collapses it`).toHaveAttribute('aria-expanded', 'false');
    await expect(calmCard.locator('app-check-rows .row').first(), `${when}: the rows are hidden`).toBeHidden();
  };

  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(calmCard).toHaveCount(1, { timeout: CARD_MS });
  await assertCards('live');

  const calmButton = calmCard.getByRole('button', { name: 'What I checked (2)', exact: true });
  await calmButton.click();
  await expect(calmButton, 'a press opens the collapsed disclosure').toHaveAttribute('aria-expanded', 'true');
  await expect(calmCard.locator('app-check-rows .row'), 'and shows both rows inline').toHaveCount(2);
  await expect(calmCard.locator('app-check-rows .row').first(), 'visible').toBeVisible();
  await expect(calmCard.locator('app-check-rows .row .word').first(), 'a passed row').toHaveText('Passed');
  await calmButton.click();
  await expect(calmButton, 'and a second press closes it').toHaveAttribute('aria-expanded', 'false');

  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await assertCards('after the reload');
});

/**
 * N17 (Story 18.4): a tell-now notice on the web chat and on the simulated phone, both with Got it. Pressing it on the web card gives "Marked as handled at
 * {time}" on the card and on the phone message, with no Got it on either, also after a reload.
 */
test('N17: Got it on the web card marks the notice handled on the card and on the phone, also after a reload', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const marker = unique('N17');
  const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary: marker, reasons: 'zz first.', confidence: 0.9, costUSD: 0.0003 });
  await sendItemDecision(user, { outcome: 'tellnow', summary: marker, decisionRef });
  const card = cardOf(page, marker);
  const message = messageOf(page, marker);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(message).toHaveCount(1, { timeout: CARD_MS });
  const cardGotIt = card.getByRole('button', { name: 'Got it', exact: true });
  const phoneGotIt = message.getByRole('button', { name: 'Got it', exact: true });
  await expect(cardGotIt, 'the web card has Got it').toHaveCount(1);
  await expect(phoneGotIt, 'and so has the phone message').toHaveCount(1);

  const sent = page.waitForRequest((request) => request.method() === 'POST' && new URL(request.url()).pathname.endsWith('/got-it'));
  await cardGotIt.click();
  expect((await sent).postDataJSON(), 'the web press sends no channel').toEqual({});
  const assertHandled = async (when: string): Promise<void> => {
    await expect(card.locator('[data-part="handled"]'), `${when}: the web card says it was handled`).toHaveText(HANDLED);
    await expect(cardGotIt, `${when}: the web card has no Got it`).toHaveCount(0);
    await expect(message.locator('.answer'), `${when}: the phone message says it was handled`).toHaveText(HANDLED);
    await expect(phoneGotIt, `${when}: the phone message has no Got it`).toHaveCount(0);
  };
  await assertHandled('after the press');
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(card).toHaveCount(1);
  await assertHandled('after the reload');
});

/** N18 (Story 18.4): the same on the simulated phone: Got it on the phone message updates the phone message and the web card. */
test('N18: Got it on the phone message marks the notice handled on the phone and on the web card', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const marker = unique('N18');
  const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary: marker, reasons: 'zz first.', confidence: 0.9, costUSD: 0.0003 });
  await sendItemDecision(user, { outcome: 'tellnow', summary: marker, decisionRef });
  const card = cardOf(page, marker);
  const message = messageOf(page, marker);
  await expect(card).toHaveCount(1, { timeout: CARD_MS });
  await expect(message).toHaveCount(1, { timeout: CARD_MS });
  const phoneGotIt = message.getByRole('button', { name: 'Got it', exact: true });
  await expect(phoneGotIt).toHaveCount(1);

  const sent = page.waitForRequest((request) => request.method() === 'POST' && new URL(request.url()).pathname.endsWith('/got-it'));
  await phoneGotIt.click();
  expect((await sent).postDataJSON(), 'the phone press sends the phone channel').toEqual({ channel: 'phone' });
  await expect(message.locator('.answer'), 'the phone message says it was handled').toHaveText(HANDLED);
  await expect(phoneGotIt, 'with no Got it').toHaveCount(0);
  await expect(card.locator('[data-part="handled"]'), 'and so does the web card').toHaveText(HANDLED);
  await expect(card.getByRole('button', { name: 'Got it', exact: true }), 'with no Got it').toHaveCount(0);
});

/**
 * N19 (Story 18.4): a digest reaches the simulated phone as one plain-text message that starts with the time-of-day greeting and ends with the previous
 * day's cost, the coverage lines in between and no Markdown.
 */
test('N19: a digest is one plain-text message on the simulated phone, from the greeting to the cost', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const marker = unique('N19');
  const parts = [
    { key: 'digest.greetingMorning', slots: {} },
    { key: 'digest.checked', slots: { checked: `the ${marker} service` } },
    { key: 'digest.savedNone', slots: {} },
    { key: 'digest.cost', slots: { cost: 0.042 } },
  ];
  const lines = [
    { key: 'digest.passed', slots: { entry: `${marker} Orders`, time: today('02:10:00') } },
    { key: 'digest.failed', slots: { entry: `${marker} Billing`, finding: '5 messages queued', time: today('02:11:00') } },
  ];
  await sendNotification(user, { kind: 'digest', catalogKey: 'checks.allPassed', slots: { parts, lines, rows: [] } });
  const message = messageOf(page, marker);
  await expect(message, 'one message').toHaveCount(1, { timeout: CARD_MS });
  const shown = (await message.locator('.text').innerText()).split('\n');
  expect(shown[0], 'it starts with the greeting').toBe('Good morning.');
  expect(shown[1], 'then what was checked').toBe(`I checked the ${marker} service.`);
  expect(shown.some((line) => line.startsWith(`Passed: ${marker} Orders (`)), 'a Passed: line').toBe(true);
  expect(shown.some((line) => line.startsWith(`Failed: ${marker} Billing (5 messages queued, `)), 'a Failed: line').toBe(true);
  expect(shown.at(-2), 'nothing saved').toBe('Nothing was saved for later.');
  expect(shown.at(-1), 'it ends with the previous day\'s cost').toBe("Yesterday's cost: $0.04.");
  expect(shown.join('\n'), 'no Markdown').not.toMatch(/[*_`#]/);
  await expect(message.getByRole('button'), 'a digest has no buttons').toHaveCount(0);
  await expect(messageOf(page, marker), 'still one message').toHaveCount(1);
});

/**
 * N11: the same untrusted item as N10's reaches the simulated phone within 5 seconds (P30, Story 2.7's phone half). The stack is in demo
 * mode, so Notify routes the notification to SimPhoneOut as well as to WebChatOut, and the phone shows its text. The clock starts before
 * the send, as N10's does, and the elapsed time is logged. The phone's text is the web card's text with its Why now line: the notice
 * of the no-key fallback.
 */
test('N11: an untrusted item reaches the simulated phone as a tell-now notification within 5 seconds', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const sender = unique('N11');
  const phone = page.getByRole('region', { name: 'Simulated devices' }).locator('app-simulated-phone');
  await expect(phone, 'the simulated phone is on the page (demo mode)').toBeVisible();
  const started = Date.now();
  await sendItem(user, { sender, subject: 'Invoice', text: 'zz body [[mock:refusal]]' });
  const message = phone.locator('.notification').filter({ hasText: sender });
  const seen = await message.waitFor({ state: 'attached', timeout: Math.max(1, FIVE_SECONDS_MS - (Date.now() - started)) }).then(
    () => true,
    () => false,
  );
  const elapsed = Date.now() - started;
  console.log(`N11: the untrusted item ${seen ? 'reached' : 'did not reach'} the simulated phone in ${elapsed} ms, counted from before the send`);
  expect(seen, 'the notification is on the simulated phone within 5 s, counted from before the send').toBe(true);
  expect(elapsed, 'in under 5000 ms').toBeLessThan(FIVE_SECONDS_MS);
  await expect(message.locator('.text'), 'with the text of the no-key fallback, on two lines').toHaveText(`${sender}: Invoice\nWhy now: no model key is set`, { useInnerText: true });
});

/**
 * N20 (Story 23.6): an incident's summary Notification through Notify is a card of the class summary: the info icon, the stored summary's catalog lines one on
 * each line with their line breaks (white-space pre-line), no heading, strip, caption or Why now line, and the cause, evidence and sample error shown as text,
 * their markup characters visible and never taken as markup. After a reload the snapshot shows the same card.
 */
test('N20: an incident summary shows as a card that keeps its line breaks and shows markup as plain text, also after a reload', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const marker = unique('N20');
  const parts = [
    { key: 'summary.title', slots: { count: 3, itemNoun: { one: 'order', other: 'orders' }, production: 'Orders' } },
    { key: 'summary.cause', slots: { cause: `${marker} sent <b>x</b> and *y* in the date.` } },
    { key: 'summary.evidence', slots: { evidence: 'OrderDate was <i>16/10/2026</i>' } },
    { key: 'summary.noFixRan', slots: {} },
    { key: 'summary.messages', slots: { failed: 3, resent: 0, completed: 0, failedAgain: 0, skipped: 0 } },
  ];
  const expected = [
    'Incident summary: 3 orders failed in Orders.',
    `Cause: ${marker} sent <b>x</b> and *y* in the date.`,
    'Evidence: OrderDate was <i>16/10/2026</i>.',
    'No fix ran, so nothing was changed.',
    'Messages: 3 failed, 0 resent, 0 completed, 0 failed again, 0 skipped.',
  ];
  const incident = await seedIncident(user, { state: 'closed', summary: JSON.stringify({ parts, lines: [] }) });
  try {
    await sendNotification(user, { kind: 'summary', catalogKey: 'summary.title', slots: {}, incidentRef: incident });
    const card = cardOf(page, marker);
    const assertCard = async (when: string): Promise<void> => {
      await expect(card, `${when}: one card`).toHaveCount(1, { timeout: CARD_MS });
      await expect(card.locator('.notice.summary'), `${when}: of the class summary`).toHaveCount(1);
      expect((await card.locator('.text').innerText()).split('\n'), `${when}: the text keeps its line breaks, one catalog line on each`).toEqual(expected);
      await expect(card.locator('.text'), `${when}: white space is kept at the line breaks`).toHaveCSS('white-space', 'pre-line');
      await expect(card.locator('.text b, .text i, .text em'), `${when}: the markup characters are text, never elements`).toHaveCount(0);
      await expect(card.locator('h1, h2, h3, h4, h5, h6, [role="heading"], .title'), `${when}: no heading or title`).toHaveCount(0);
      await expect(card.locator('app-decision-strip, .caption, .why'), `${when}: no strip, caption or Why now line`).toHaveCount(0);
      await expect(card.getByRole('button'), `${when}: no button`).toHaveCount(0);
    };
    await assertCard('arrived');
    await expect(card.locator('.notice > app-icon'), 'in the info ink').toHaveCSS('color', await tokenColor(page, '--info-ink'));
    await loadedAfter(page, () => page.reload());
    await assertCard('after a reload');
  } finally {
    await cleanFixtureRows([incident]);
  }
});

/**
 * N21 (Story 23.5, AC-NOTDRAFTED-WEB; QA): the notice that a delay notice could not be drafted (result.partnerNotDrafted: kind result, no approvalRef) through Notify, WebChatOut and the
 * live store is a notice card of the chat: the ruled text as one piece, the info icon, no heading, no button, and it is still there after a reload. A fix's result has no card of its
 * own in the chat (its incident card draws it), so this is the one result that has no approvalRef and still shows.
 */
test('N21: a delay notice that could not be drafted shows as a notice card, also after a reload', async ({ page }) => {
  const { user } = fixtureUser('NOTICE');
  await open(page);
  const text = "I couldn't draft the delay notice just now, so nothing was raised or sent. You can ask me again.";
  const card = page.locator('app-chat-panel app-notice-card').filter({ hasText: text });
  const before = await card.count();
  await sendNotification(user, { kind: 'result', catalogKey: 'result.partnerNotDrafted', slots: {} });
  const assertCard = async (when: string): Promise<void> => {
    await expect(card, `${when}: the card`).toHaveCount(before + 1, { timeout: CARD_MS });
    const last = card.last();
    await expect(last.locator('.text'), `${when}: the ruled text`).toHaveText(text);
    await expect(last.locator('.notice > app-icon'), `${when}: in the info ink`).toHaveCSS('color', await tokenColor(page, '--info-ink'));
    await expect(last.locator('h1, h2, h3, h4, h5, h6, [role="heading"], .title, .why, .caption, app-decision-strip'), `${when}: no heading, Why now line, caption or strip`).toHaveCount(0);
    await expect(last.getByRole('button'), `${when}: no button`).toHaveCount(0);
  };
  await assertCard('arrived');
  await loadedAfter(page, () => page.reload());
  await assertCard('after a reload');
});
