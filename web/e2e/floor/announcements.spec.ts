import { expect, test, type Locator, type Page } from '@playwright/test';

import { MESSAGES, STATE, holdPoll, sessionEvents, type LiveEvent } from '../support/api';
import { signIn, signInOverHttp } from '../sign-in/helpers';
import {
  cleanFixtureRows,
  finishTurn,
  fixtureUser,
  publishReminder,
  publishStatus,
  seedDecision,
  seedReminder,
  seedTurns,
  sendItemDecision,
  sendNotification,
  sinkEvent,
} from '../support/iris';
import { CARD_MS, banner, composerOf, inMs, mainOf, railOf, replyOf, unique } from '../support/floor';
import { announcedTexts, announcedTimes, recordAnnouncements } from '../support/page';

/**
 * Story 2.12, what the page announces (A1 to A7), in a real browser against a real stack. It pins that the page speaks through one
 * polite live region and says each event once: a reply, a tell-now card, a reminder card, a banner and a failed send, never the first
 * snapshot, the user's own messages, Working or a timer (no case here shows Deciding: chat-announcements.test.mjs pins that it is
 * silent); that the messages of one update are one text and a burst of four is
 * "4 new updates"; and that the chat, the rail, the turn indicator and the timers are no live region. It needs the stack that
 * docker/tests/test-floor.sh starts: every case signs in as the floor user (OCUTALON_FLOOR_USER, the user role) over real HTTP, whose
 * session only the floor specs use, and records what the live region received before it signs in (recordAnnouncements).
 *
 * "One update" is a held poll (holdPoll): the case holds the page's next /events request, seeds and publishes while it is held, and
 * then lets it continue, so that everything arrives in one answer. A production send such as a tell-now card is waited for in the
 * server's own stream (sessionEvents) before the release. Every case runs on Playwright's clock in the page (open installs it), and
 * holdPoll stops that clock while the poll is held: however long a slow host takes to seed, the page counts no silence, so
 * Reconnecting (10 s after the page's last answer) cannot show and change what a case counts.
 * The chat posts of A6 are answered in the browser and never reach the server, so no turn of these cases replies, up to 20 s later,
 * inside another case's window, in either order. A case that turns conditions on turns them off in finally (A4 and A5 also start with
 * them off), a case that registers fixture rows removes them with cleanFixtureRows in finally, and a running turn is finished in
 * finally. The turns and cards a case seeds stay on the floor user's session and are found by their own marker or ref; the seeded
 * turns are dated in 2019, so they are the oldest entries of the chat and cannot push what a case makes now out of the newest 100
 * that /state serves.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll or a post that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';

/** How long a case looks on after the announcements it expects: longer than the 1 s between two texts, so a second one would show. */
const SETTLE_MS = 3000;

/** The fixed words of the announcements, written out here as the independent oracle of the page's own. */
const NOT_SENT = 'Message not sent';
const FOUR = '4 new updates';

const cardOf = (page: Page, marker: string): Locator => page.locator('app-chat-panel app-notice-card').filter({ hasText: marker });

/** Today's date (UTC) with the time given, as a UTC ISO time. */
const today = (time: string): string => `${new Date().toISOString().slice(0, 10)}T${time}Z`;

/**
 * Signs the floor user in, having put Playwright's clock in the page (it runs on with the host's clock until holdPoll stops it) and recorded
 * what the live region receives, and waits for the loaded page with its composer.
 */
async function open(page: Page): Promise<void> {
  await page.clock.install();
  await recordAnnouncements(page);
  const { user, password } = fixtureUser(KIND);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

/** The last Seq of the session's stream that the page has applied. */
const appliedSeq = async (page: Page): Promise<number> => Number(await mainOf(page).getAttribute('data-session-seq'));

/** Waits until the server's own session stream, after the cursor, holds a notification event of the kind, and returns it. */
async function cardEvent(page: Page, after: number, kind: string): Promise<LiveEvent> {
  const events = await sessionEvents(page.request, after, (seen) => seen.some((event) => event.type === 'notification' && event.payload['kind'] === kind), 20);
  const found = events.find((event) => event.type === 'notification' && event.payload['kind'] === kind);
  expect(found, `the production put a ${kind} card on the session's stream`).toBeDefined();
  return found!;
}

/**
 * Expects the live region to have received exactly these texts, in order: it waits for them, then looks on for SETTLE_MS, so that a
 * second announcement of the same update, or a late one, would show.
 */
async function heard(page: Page, expected: string[]): Promise<void> {
  await expect.poll(() => announcedTexts(page), { message: 'the page announces what it should', timeout: CARD_MS }).toEqual(expected);
  await page.waitForTimeout(SETTLE_MS);
  expect(await announcedTexts(page), 'and nothing else, also later').toEqual(expected);
}

/** Turns the conditions on, as StatusMonitor would. */
async function conditionsOn(user: string): Promise<void> {
  await publishStatus(user, { condition: 'heartbeatStalled', active: true, slots: { time: today('11:00:00') } });
  await publishStatus(user, { condition: 'resetSoon', active: true });
}

/** Turns the conditions off again, so that no later case's first snapshot shows them. */
async function conditionsOff(user: string): Promise<void> {
  await publishStatus(user, { condition: 'heartbeatStalled', active: false });
  await publishStatus(user, { condition: 'resetSoon', active: false });
}

/** The two banners of conditionsOn as they stand in the stack, in stack order, with their texts. */
async function stalledAndReset(page: Page): Promise<string[]> {
  const both = page.locator('app-banner-stack [data-banner="heartbeatStalled"], app-banner-stack [data-banner="resetSoon"]');
  await expect(both, 'both banners show').toHaveCount(2, { timeout: CARD_MS });
  const ids = await both.evaluateAll((nodes) => nodes.map((node) => node.getAttribute('data-banner')));
  expect(ids, 'in stack order').toEqual(['heartbeatStalled', 'resetSoon']);
  return (await both.locator('.text').allTextContents()).map((text) => text.trim());
}

/**
 * A1: a reply is announced once, as "OcuTalon replied:" and its first sentence, whether it is the model's text or a fallback's
 * catalog sentence; the turn's own text and Working are not.
 */
test('A1: a reply is announced once, as OcuTalon replied and its first sentence', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  let running: string | undefined;
  try {
    await open(page);
    const question = `zz A1 question ${Date.now().toString(36)}`;
    const { refs } = await seedTurns(user, [{ createdAt: '2019-01-01T10:00:00Z', text: question, replyText: '', state: 'running' }], true);
    const ref = refs[0]!;
    running = ref;
    await expect(replyOf(page, ref).locator('.indicator'), 'the running turn shows its indicator').toHaveText('Working\u2026', { timeout: CARD_MS });
    await expect(page.locator('app-chat-panel .bubble').filter({ hasText: question }), 'and its message').toHaveCount(1);
    await page.waitForTimeout(SETTLE_MS);
    expect(await announcedTexts(page), 'neither the message nor Working is announced').toEqual([]);

    await finishTurn(user, ref, 'zz A1 See [the guide](https://example.com/guide) here. Second sentence.');
    running = undefined;
    await expect(replyOf(page, ref).locator('.text'), 'the reply shows').toContainText('Second sentence.', { timeout: CARD_MS });
    await expect(replyOf(page, ref).getByRole('link', { name: /the guide/ }), 'with its link').toHaveCount(1);
    await expect.poll(() => announcedTexts(page), { message: 'the reply is announced as the page shows it: the link as its label', timeout: CARD_MS }).toEqual(['OcuTalon replied: zz A1 See the guide here.']);
    await expect(page.locator('[aria-live]'), 'in the polite region').toHaveAttribute('aria-live', 'polite');

    const fallback = await seedTurns(
      user,
      [{ createdAt: '2019-01-01T10:01:00Z', text: `zz A1 fallback ${Date.now().toString(36)}`, replyText: '', catalogKey: 'conversation.turnFallback', fallbackReason: 'no_key' }],
      true,
    );
    await expect(replyOf(page, fallback.refs[0]!).locator('.text'), 'a fallback reply shows the catalog sentence').toHaveText("I couldn't answer that: no model key is set. Nothing was changed.", { timeout: CARD_MS });
    await heard(page, ['OcuTalon replied: zz A1 See the guide here.', "OcuTalon replied: I couldn't answer that: no model key is set."]);
  } finally {
    if (running !== undefined) await finishTurn(user, running, 'zz A1 finished');
  }
});

/** A2: a tell-now card and its rail row arrive in one update; the card is announced once, the rail adds nothing. */
test('A2: a tell-now card is announced once as Tell now and its first sentence, though the rail shows its decision', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    await open(page);
    const marker = unique('A2');
    const summary = `${marker} Orders are failing. More.`;
    const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary, reasons: 'zz first.\nzz second.', confidence: 0.9, costUSD: 0.0003 });
    refs.push(decisionRef);
    const after = await appliedSeq(page);
    const release = await holdPoll(page);
    await sinkEvent(user, 'decision.recorded', { ref: decisionRef });
    await sendItemDecision(user, { outcome: 'tellnow', summary, decisionRef });
    await cardEvent(page, after, 'tellnow');
    await release();

    await expect(cardOf(page, marker), 'the card shows').toHaveCount(1, { timeout: CARD_MS });
    await expect(railOf(page).locator('app-decision-row').filter({ hasText: marker }), 'and so does the decision row').toHaveCount(1);
    await heard(page, [`Tell now: ${marker} Orders are failing.`]);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** A3: a reminder fires: its row leaves and its card arrives in one update, and the card's text is announced once. */
test('A3: a reminder card is announced once as its text, though its row leaves the rail', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  try {
    const text = unique('A3 stretch');
    const dueAt = inMs(300_000);
    const ref = await seedReminder(user, { text, dueAt });
    refs.push(ref);
    await open(page);
    const row = railOf(page).locator('li.row').filter({ hasText: text });
    await expect(row, 'the pending reminder shows in the rail').toHaveCount(1);
    const after = await appliedSeq(page);
    const release = await holdPoll(page);
    await publishReminder(user, { ref, text, dueAt, state: 'fired' });
    await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text, dueAt: today('12:00:00') } });
    await cardEvent(page, after, 'reminder');
    await release();

    await expect(row, 'the fired reminder leaves the rail').toHaveCount(0, { timeout: CARD_MS });
    await expect(cardOf(page, text), 'and its card is in the chat').toHaveCount(1);
    await heard(page, [`Reminder: ${text}.`]);
  } finally {
    await cleanFixtureRows(refs);
  }
});

/** A4 (DW-153): two banners that one poll brings are one text, in stack order, and neither is heard alone. */
test('A4: two banners that appear in one update are announced as one text, in stack order', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  try {
    await conditionsOff(user);
    await open(page);
    const release = await holdPoll(page);
    await conditionsOn(user);
    await release();

    const [stalled, reset] = await stalledAndReset(page);
    expect(reset, 'Reset soon says what the catalog says').toBe('The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.');
    await heard(page, [`${stalled} ${reset}`]);
  } finally {
    await conditionsOff(user);
  }
});

/** A5: two banners and two replies in one update are four messages: "4 new updates", and none of their texts. */
test('A5: a burst of two banners and two replies in one update is announced as 4 new updates', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  try {
    await conditionsOff(user);
    await open(page);
    const release = await holdPoll(page);
    await conditionsOn(user);
    const { refs } = await seedTurns(
      user,
      [
        { createdAt: '2019-05-01T10:00:00Z', text: 'zz A5 first', replyText: 'zz A5 first reply. More.' },
        { createdAt: '2019-05-01T10:01:00Z', text: 'zz A5 second', replyText: 'zz A5 second reply. More.' },
      ],
      true,
    );
    await release();

    await stalledAndReset(page);
    await expect(replyOf(page, refs[0]!).locator('.text'), 'the first reply shows').toHaveText('zz A5 first reply. More.');
    await expect(replyOf(page, refs[1]!).locator('.text'), 'and the second').toHaveText('zz A5 second reply. More.');
    await heard(page, [FOUR]);
  } finally {
    await conditionsOff(user);
  }
});

/**
 * A6: a failed send is announced each time and the typed text never. The second text lands about a second after the first: the
 * case allows 800 ms for the browser's timers, and announce-queue.test.mjs pins the exact 1000 ms on a fake clock. A post that is
 * answered 401 is the session gate's and announces nothing (its sign-in page navigation is cancelled here, so that the page lives
 * on to be read).
 */
test('A6: each failed send is announced as Message not sent, and the typed text and a 401 are not', async ({ page }) => {
  await open(page);
  let status = 500;
  let posts = 0;
  let navigations = 0;
  await page.route(/\/ocutalon\/\?signedOut=1/, async (route) => {
    navigations += 1;
    await route.abort('aborted');
  });
  await page.route(`**${MESSAGES}`, async (route) => {
    posts += 1;
    const body = status === 401 ? '{"error":{"code":"signed_out"}}' : '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}';
    await route.fulfill({ status, contentType: 'application/json', body });
  });
  const typed = `zz A6 typed ${Date.now().toString(36)}`;
  const field = composerOf(page);
  await field.fill(typed);
  await field.press('Enter');
  await expect.poll(() => announcedTexts(page), { message: 'the failed send is announced', timeout: CARD_MS }).toEqual([NOT_SENT]);
  const bubble = page.locator('app-chat-panel .bubble').filter({ hasText: typed });
  await expect(bubble, 'the message shows in the chat').toHaveCount(1);
  await expect(page.locator('app-chat-panel .failed')).toHaveText('Not sent');

  await page.getByRole('button', { name: 'Retry sending', exact: true }).click();
  await expect.poll(() => announcedTexts(page), { message: 'a retry that fails is announced again', timeout: CARD_MS }).toEqual([NOT_SENT, NOT_SENT]);
  const [first, second] = await announcedTimes(page);
  expect(second! - first!, 'the second text lands about a second after the first').toBeGreaterThanOrEqual(800);
  await page.waitForTimeout(SETTLE_MS);
  expect(await announcedTexts(page), 'nothing else, and never the typed text').toEqual([NOT_SENT, NOT_SENT]);
  expect(posts, 'two posts were answered in the browser, and none reached the server').toBe(2);

  status = 401;
  await page.getByRole('button', { name: 'Retry sending', exact: true }).click();
  await expect.poll(() => navigations, { message: 'the 401 sends the page to the sign-in page', timeout: CARD_MS }).toBe(1);
  await page.waitForTimeout(SETTLE_MS);
  expect(await announcedTexts(page), 'a 401 is the session gate\'s and announces nothing').toEqual([NOT_SENT, NOT_SENT]);
  expect(posts, 'three posts were answered in the browser, and none reached the server').toBe(3);
});

/** A7: one live region, a silent first snapshot, and no announcement from the chat, the rail, the indicator or a ticking timer. */
test('A7: the page has one live region, and announces nothing from the first snapshot or from its timers', async ({ page, request }) => {
  const { user, password } = fixtureUser(KIND);
  const refs: string[] = [];
  let running: string | undefined;
  try {
    await signInOverHttp(request, user, password);
    const state = (await (await request.get(STATE)).json()) as { streams: { session: number } };
    const after = state.streams.session;
    const seeded = await seedTurns(user, [
      { createdAt: '2019-07-01T10:00:00Z', text: 'zz A7 running', replyText: '', state: 'running' },
      { createdAt: '2019-07-01T10:01:00Z', text: 'zz A7 done', replyText: 'zz A7 reply. More.' },
    ]);
    running = seeded.refs[0];
    const dueAt = inMs(58_000);
    const countdownText = unique('A7 countdown');
    const cardText = unique('A7 card');
    refs.push(await seedReminder(user, { text: countdownText, dueAt }));
    await sendNotification(user, { kind: 'reminder', catalogKey: 'reminder.due', slots: { text: cardText, dueAt: today('12:00:00') } });
    const events = await sessionEvents(request, after, (seen) => seen.some((event) => event.type === 'notification'), 20);
    expect(events.some((event) => event.type === 'notification'), "the card is on the session's stream, so the first snapshot holds it").toBe(true);

    await open(page);
    const indicator = replyOf(page, running!).locator('.indicator');
    await expect(indicator, 'the first snapshot shows a running turn').toHaveText('Working\u2026');
    await expect(replyOf(page, seeded.refs[1]!).locator('.text'), 'a done turn with its reply').toHaveText('zz A7 reply. More.');
    await expect(cardOf(page, cardText), 'a notice card').toHaveCount(1);
    const countdown = railOf(page).locator('li.row').filter({ hasText: countdownText }).locator('.countdown');
    await expect(countdown, 'and a reminder whose countdown ticks').toHaveCount(1);
    await expect(banner(page, 'noModelKey'), 'and the no-key banner').toHaveCount(1);

    const live = page.locator('[aria-live]');
    await expect(live, 'one element of the page is a live region').toHaveCount(1);
    await expect(live, 'the announcer\'s own').toHaveClass(/cdk-live-announcer-element/);
    await expect(live, 'which is polite').toHaveAttribute('aria-live', 'polite');
    await expect(page.locator('[role="log"], [role="status"], [role="alert"], [role="timer"], [role="marquee"]'), 'no element has a live role').toHaveCount(0);
    const places: Array<[string, Locator]> = [
      ['the chat list', page.locator('app-chat-panel .list')],
      ['the rail', railOf(page)],
      ['the turn indicator', indicator],
      ['the countdown', countdown],
    ];
    for (const [name, place] of places) {
      for (const attribute of ['aria-live', 'aria-atomic', 'aria-relevant']) {
        await expect(place, `${name} has no ${attribute}`).not.toHaveAttribute(attribute, /.*/);
        await expect(place.locator(`[${attribute}]`), `nor does anything in ${name}`).toHaveCount(0);
      }
    }

    const before = await countdown.textContent();
    await page.waitForTimeout(SETTLE_MS);
    expect(await countdown.textContent(), 'the countdown ticked').not.toBe(before);
    expect(await announcedTexts(page), 'and nothing at all has been announced since sign-in').toEqual([]);
  } finally {
    if (running !== undefined) await finishTurn(user, running, 'zz A7 finished');
    await cleanFixtureRows(refs);
  }
});
