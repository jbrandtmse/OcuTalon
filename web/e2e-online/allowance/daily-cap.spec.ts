import { expect, test, type Browser, type BrowserContext, type Locator, type Page } from '@playwright/test';

import { post, MESSAGES } from '../../e2e/support/api';
import {
  allowanceRow,
  answerApproval,
  cappedMarked,
  cleanPopulated,
  clearOfMidnight,
  dailyCapSettled,
  epochOf,
  fallbackReasons,
  mockRequests,
  populate,
  removeSession,
  removeUsage,
  seedAllowance,
  seedUsage,
  signInFromSplash,
  signOutGroup,
  turnRowsOf,
  unmarkCapped,
  type Populated,
} from '../support';

/**
 * Story 16.9, the online demo's daily cost cap (D1, D2 and AP; matrix rows 13 to 16; AC 5 and 8). The project runs on its own online-demo
 * throwaway with the daily cap at $20 and the runners' keys pointed at the CI mock, so that a decision reaches the cap before it reaches a
 * missing key. The cap is instance-wide, so the cases run in order (serial), and each `finally` deletes the Usage row it seeded and kills the
 * day's capped mark, so that the next case starts clean; D2 and AP then wait until StatusMonitor has published the cap's clear. Every
 * case signs out of the whole sign-in group and removes the rows it made.
 * - D1 (IRIS's own count of the spend): S3 signs in and sends one message and S2 signs in and stays idle; a Usage row of $20 is seeded for
 *   today; S1 sends, and its reply is the daily_cap fallback. S1 has one daily-cap card (an "ET" time and the install link), S3 has one from
 *   the broadcast of budget.capped, S2 has none until its own send and then one, and another send from S1 adds none. The "daily cap" banner
 *   shows on all three once S1's fallback has marked the day (a web process counts only that mark and the gateway's spend), the composer stays
 *   usable and DailyCapDay is today on all three.
 * - D2 (the gateway's 403): from the clean state, S4 sends [[mock:daily-cap]]: its decision falls back with daily_cap, the mock log shows one
 *   such request, the day is marked, the banner shows and one card follows.
 * - AP (both caps hold): S1 is capped and has an allowance window (a seeded hour and one 429), a real Orders watch and a fixture approval:
 *   Approval.Answer answers the approval with done, and pressing Break the feed in the page answers 200.
 * - D0 (DW-413, browserless): clearOfMidnight waits past instance midnight and reads the day again when a case's budget does not fit in what is
 *   left of the day, and returns at once when it does.
 * D1, D2 and AP call clearOfMidnight first and use its day for every mark, check and cleanup, so that the day cannot turn inside a case.
 * The texts are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ mode: 'serial', timeout: 300_000 });

const INSTALL = 'https://github.com/jbrandtmse/OcuTalon#install-it-yourself';
const CAPPED_CARD = "The online demo has used today's model allowance. Decisions use fixed rules until ";
const MARKER = '[[mock:daily-cap]]';

/** The seconds of the instance's day that each case needs (its waits, with a margin): clearOfMidnight waits past midnight when fewer are left. */
const D1_BUDGET_S = 240;
const D2_BUDGET_S = 150;
const AP_BUDGET_S = 200;

const mainOf = (page: Page): Locator => page.locator('main.main');
const composer = (page: Page): Locator => page.getByRole('textbox', { name: 'Message OcuTalon' });
const cappedCards = (page: Page): Locator => page.locator('app-notice-card').filter({ hasText: CAPPED_CARD });
const dailyCapBanner = (page: Page): Locator => page.locator('[data-banner="dailyCap"]');

/** A visitor: its own browser context, signed in at the splash, with the epoch of its session. */
interface Visitor {
  context: BrowserContext;
  page: Page;
  epoch: string;
}

/** Signs a new visitor in, in a context of its own (a new OcuTalon session with its own resume cookie), once its snapshot has loaded. */
async function visit(browser: Browser): Promise<Visitor> {
  const context = await browser.newContext({ baseURL: process.env['OCUTALON_URL'] });
  const page = await context.newPage();
  await signInFromSplash(page);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  return { context, page, epoch: await epochOf(page) };
}

/** Signs a visitor out and removes its rows. */
async function leave(visitor: Visitor | undefined): Promise<void> {
  if (visitor === undefined) return;
  await signOutGroup(visitor.context);
  await removeSession(visitor.epoch);
  await visitor.context.close();
}

/** Sends a message through the API of the visitor's page. */
async function send(visitor: Visitor, text: string, id: string): Promise<void> {
  const answered = await post(visitor.page.request, MESSAGES, { clientId: `zz-cap-${id}-${visitor.epoch.slice(0, 6)}`, text, fromGuide: false });
  expect(answered.status(), `${id}: the message is accepted`).toBe(202);
}

/**
 * Waits, after a case has restored the cap, until StatusMonitor has published the cap's clear (or never published the cap): the monitor
 * remembers the dailyCap it published, so a cap that is lifted and reached again before its next run is no change to it and publishes
 * nothing, which a page that loaded in between would never see.
 */
async function settleMonitor(): Promise<void> {
  await expect.poll(dailyCapSettled, { message: 'StatusMonitor remembers the daily cap as lifted', timeout: 90_000, intervals: [1_000] }).toBe(true);
}

/** Restores what a case changed instance-wide: its Usage row and the capped mark of the day that it used (undefined when it never read one). */
async function restore(day: string | undefined, usage: string | undefined): Promise<void> {
  if (usage !== undefined) await removeUsage(usage);
  if (day !== undefined) await unmarkCapped(day);
}

test('D0: clearOfMidnight waits past instance midnight when the budget does not fit in the day, and reads the day once more', async () => {
  const slept: number[] = [];
  const sleep = async (ms: number): Promise<void> => {
    slept.push(ms);
  };
  const readings = [
    { day: '2026-10-30', secondsLeft: 2 },
    { day: '2026-10-31', secondsLeft: 86_398 },
  ];
  const day = await clearOfMidnight(100, async () => readings.shift()!, sleep);
  expect(slept, 'one sleep of the 2 seconds left plus 2').toEqual([4000]);
  expect(day, 'the day after midnight').toBe('2026-10-31');
  expect(readings, 'the day was read twice and no more').toEqual([]);

  slept.length = 0;
  const early = [{ day: '2026-10-30', secondsLeft: 100 }];
  expect(await clearOfMidnight(100, async () => early.shift()!, sleep), 'a budget that just fits returns the day at once').toBe('2026-10-30');
  expect(slept, 'with no sleep').toEqual([]);
});

test('D1: the daily cap reached by IRIS\'s own count sends the daily-cap message once to each session with activity', async ({ browser }) => {
  let s1: Visitor | undefined;
  let s2: Visitor | undefined;
  let s3: Visitor | undefined;
  let usage: string | undefined;
  let day: string | undefined;
  test.setTimeout(300_000 + D1_BUDGET_S * 1000);
  try {
    day = await clearOfMidnight(D1_BUDGET_S);
    expect(await cappedMarked(day), 'the day is not marked to begin with').toBe(false);
    s3 = await visit(browser);
    await send(s3, 'zz S3 before the cap', 'd1s3');
    await expect.poll(async () => (await turnRowsOf(s3!.epoch)).map((turn) => turn.state), { message: "S3's turn is done before the cap is reached", timeout: 90_000 }).toEqual(['done']);
    s2 = await visit(browser);
    usage = await seedUsage(20);
    s1 = await visit(browser);
    await send(s1, 'zz S1 under the cap', 'd1s1');

    await expect(cappedCards(s1.page), 'S1 has one daily-cap card').toHaveCount(1, { timeout: 90_000 });
    expect(await fallbackReasons(s1.epoch), "S1's decision fell back with daily_cap").toContain('daily_cap');
    await expect(cappedCards(s1.page).first()).toContainText(' ET. You can install OcuTalon yourself to keep going: ');
    await expect(cappedCards(s1.page).first()).toContainText(INSTALL);
    await expect(cappedCards(s3.page), 'S3 has one, from the broadcast').toHaveCount(1, { timeout: 60_000 });
    await page2Quiet(s2);
    await expect(cappedCards(s2.page), 'S2 has none until its own send').toHaveCount(0);

    await send(s1, 'zz S1 again', 'd1s1b');
    await send(s2, 'zz S2 wakes', 'd1s2');
    await expect(cappedCards(s2.page), 'S2 has one after its own send').toHaveCount(1, { timeout: 90_000 });
    await s1.page.waitForTimeout(5000);
    await expect(cappedCards(s1.page), 'another send from S1 adds none').toHaveCount(1);
    expect(await cappedMarked(day), "S1's fallback marked the day").toBe(true);

    for (const [name, visitor] of [['S1', s1], ['S2', s2], ['S3', s3]] as const) {
      await expect(dailyCapBanner(visitor.page), `${name}: the "daily cap" banner shows`).toBeVisible({ timeout: 60_000 });
      await expect(composer(visitor.page), `${name}: the composer stays usable`).not.toHaveAttribute('aria-disabled', 'true');
    }
    for (const [name, visitor] of [['S1', s1], ['S2', s2], ['S3', s3]] as const) {
      expect((await allowanceRow(visitor.epoch)).dailyCapDay, `${name}: DailyCapDay is today`).toBe(day);
    }
  } finally {
    await leave(s1);
    await leave(s2);
    await leave(s3);
    await restore(day, usage);
  }
});

/** Gives a visitor's page a moment, so that a card that would be sent to it has had its time to arrive. */
async function page2Quiet(visitor: Visitor): Promise<void> {
  await visitor.page.waitForTimeout(8000);
}

test('D2: the gateway\'s 403 falls back with daily_cap, marks the day and sends the message once', async ({ browser }) => {
  let s4: Visitor | undefined;
  let day: string | undefined;
  test.setTimeout(300_000 + D2_BUDGET_S * 1000);
  try {
    day = await clearOfMidnight(D2_BUDGET_S);
    expect(await cappedMarked(day), 'the clean state: the day is not marked').toBe(false);
    await settleMonitor();
    const before = await mockRequests('daily-cap');
    s4 = await visit(browser);
    await send(s4, `${MARKER} zz capped by the gateway`, 'd2');
    await expect(cappedCards(s4.page), 'one daily-cap card').toHaveCount(1, { timeout: 90_000 });
    expect(await fallbackReasons(s4.epoch), 'its decision fell back with daily_cap').toContain('daily_cap');
    expect(await cappedMarked(day), 'the day is marked').toBe(true);
    expect((await mockRequests('daily-cap')) - before, 'the mock saw one request').toBe(1);
    await expect(dailyCapBanner(s4.page), 'the banner shows').toBeVisible({ timeout: 60_000 });
    await s4.page.waitForTimeout(5000);
    await expect(cappedCards(s4.page), 'and still one card').toHaveCount(1);
    expect((await allowanceRow(s4.epoch)).dailyCapDay).toBe(day);
  } finally {
    await leave(s4);
    await restore(day, undefined);
  }
});

test('AP: an approval is answered and Break the feed is pressed while both caps hold', async ({ browser }) => {
  let s1: Visitor | undefined;
  let usage: string | undefined;
  let rows: Populated | undefined;
  let day: string | undefined;
  test.setTimeout(300_000 + AP_BUDGET_S * 1000);
  try {
    day = await clearOfMidnight(AP_BUDGET_S);
    expect(await cappedMarked(day), 'the clean state: the day is not marked').toBe(false);
    await settleMonitor();
    s1 = await visit(browser);
    usage = await seedUsage(20);
    await send(s1, 'zz S1 under the cap', 'apcap');
    await expect(cappedCards(s1.page), 'the daily cap holds for S1').toHaveCount(1, { timeout: 90_000 });
    await seedAllowance(s1.epoch, 50, 100);
    await composer(s1.page).fill('zz refused');
    const refused = s1.page.waitForResponse((response) => response.url().includes('/api/v1/messages') && response.status() === 429);
    await s1.page.locator('app-composer').getByRole('button', { name: 'Send', exact: true }).click();
    await refused;
    await expect(s1.page.locator('[data-banner="allowance"]'), 'and so does its allowance window').toBeVisible();

    const ref = (await allowanceRow(s1.epoch)).ref;
    rows = await populate(ref);
    expect(await answerApproval(ref, rows.approval, 'approve'), 'the approval is answered through Approval.Answer').toBe('done');
    await s1.page.reload();
    await expect(mainOf(s1.page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(s1.page.locator('[data-banner="allowance"]'), 'the allowance window holds after a reload').toBeVisible();
    const button = s1.page.locator('app-break-feed-box app-server-button button');
    await expect(button, 'Break the feed is not disabled by either cap').not.toHaveAttribute('aria-disabled', 'true');
    const pressed = s1.page.waitForResponse((response) => response.url().includes('/api/v1/demo/break-feed') && response.request().method() === 'POST');
    await button.click();
    expect((await pressed).status(), 'Break the feed answers 200').toBe(200);
  } finally {
    if (rows !== undefined) await cleanPopulated(rows);
    await leave(s1);
    await restore(day, usage);
  }
});
