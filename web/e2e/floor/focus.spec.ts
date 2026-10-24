import { expect, test, type Locator, type Page, type Route } from '@playwright/test';

import { MESSAGES, STATE } from '../support/api';
import { signIn } from '../sign-in/helpers';
import {
  cleanFixtureRows,
  finishTurn,
  fixtureUser,
  publishCheck,
  publishReminder,
  publishStatus,
  seedCheck,
  seedDecision,
  seedTurns,
  sendItemDecision,
} from '../support/iris';
import { countFocusins, focusinCount } from '../support/page';

/**
 * Story 2.12, where focus goes (P1 to P4), in a real browser against a real stack. It pins the page's one focus rule
 * (shared/focus-rule.ts): when an update removes the element that holds focus, focus goes to its replacement, or to the heading of
 * the section a row left, or to the main region, and in no other case does live content move it. It needs the stack that
 * docker/tests/test-floor.sh starts: every case signs in as the floor user (OCUTALON_FLOOR_USER, the user role) over real HTTP.
 * The chat posts of P1 are answered or held in the browser and never reach the server, so no turn of these cases replies, up to 20 s
 * later, inside another case's window, in either order. P4, the one case that turns a condition on, starts with it off and turns it off
 * in finally, finishes its running turn and removes its fixture rows with cleanFixtureRows in finally; the other cases leave nothing
 * behind that outlives the page (P2's reminder is an event, fired in the case). Every case starts in a fresh browser context, so the
 * sign-in help of P2 is unseen in it.
 */
test.describe.configure({ timeout: 90_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

/** A poll or a post that a routed handler is still holding when a test ends must not fail the next test. */
test.afterEach(async ({ page }) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
});

const KIND = 'FLOOR';

/** How long a card may take to reach the page after the send returns: the route, the live poll (1 to 2 s) and the render. */
const CARD_MS = 15_000;

/** The answer of a server that failed. */
const SERVER_ERROR = '{"error":{"code":"server_error","message":"Something went wrong inside OcuTalon. Try again."}}';

/** The header of a trace that no run made: the link only needs an address to open. */
const HEADER = 4242;

const mainOf = (page: Page): Locator => page.locator('main.main');
const railOf = (page: Page): Locator => page.getByRole('region', { name: 'Status', exact: true });
const composerOf = (page: Page): Locator => page.getByRole('textbox', { name: 'Message OcuTalon' });
const replyOf = (page: Page, key: string): Locator => page.locator(`app-chat-panel [data-part="reply"][data-key="${key}"]`);
const rowOf = (page: Page, marker: string): Locator => railOf(page).locator('li.row').filter({ hasText: marker });
const banner = (page: Page, id: string): Locator => page.locator(`app-banner-stack [data-banner="${id}"]`);

/** A text no other case or run made. */
const unique = (label: string): string => `zz ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** An ISO time to the second, the given number of milliseconds from now. */
const inMs = (ms: number): string => new Date(Date.now() + ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

/** What the page's document.activeElement is, in words a failure message can show. */
const activeOf = (page: Page): Promise<string> =>
  page.evaluate(() => {
    const active = document.activeElement;
    return active === null ? 'null' : `${active.tagName.toLowerCase()}${active.id ? `#${active.id}` : ''}${active.getAttribute('data-part') ? `[data-part=${active.getAttribute('data-part')}]` : ''}`;
  });

/** Signs the floor user in and waits for the loaded page with its composer. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

/** Waits until the page has applied the event of this Seq on the session's stream. */
async function applied(page: Page, seq: number): Promise<void> {
  await expect
    .poll(async () => Number(await mainOf(page).getAttribute('data-session-seq')), { message: `the page applied Seq ${seq}`, timeout: CARD_MS })
    .toBeGreaterThanOrEqual(seq);
}

/** P1: Retry sending leaves focus on its message while the post is out, and nothing moves it when the post fails again. */
test('P1: Retry sending leaves focus on its message, and it stays there when the post fails again', async ({ page }) => {
  await open(page);
  let mode: 'fail' | 'hold' = 'fail';
  let held: Route | undefined;
  let posts = 0;
  await page.route(`**${MESSAGES}`, async (route) => {
    posts += 1;
    if (mode === 'hold') {
      held = route;
      return;
    }
    await route.fulfill({ status: 500, contentType: 'application/json', body: SERVER_ERROR });
  });
  const typed = unique('P1');
  const field = composerOf(page);
  await field.fill(typed);
  await field.press('Enter');
  const message = page.locator('app-chat-panel [data-part="user"]').filter({ hasText: typed });
  const retry = message.getByRole('button', { name: 'Retry sending', exact: true });
  await expect(retry, 'the failed message offers Retry sending').toBeVisible({ timeout: CARD_MS });
  await retry.focus();
  await expect(retry, 'and holds focus').toBeFocused();

  mode = 'hold';
  await page.keyboard.press('Enter');
  await expect.poll(() => held !== undefined, { message: 'the retry posted again and the route holds that post' }).toBe(true);
  await expect(retry, 'while the post is out the button is gone').toHaveCount(0);
  await expect(message, 'and focus is on its message').toBeFocused();
  expect(await activeOf(page), 'not on the body').toBe('div[data-part=user]');

  await held!.fulfill({ status: 500, contentType: 'application/json', body: SERVER_ERROR });
  await expect(message.getByText('Not sent'), 'the failed post says Not sent again').toBeVisible({ timeout: CARD_MS });
  await expect(retry, 'with Retry sending back').toBeVisible();
  await expect(message, 'and focus stays on the message: nothing moves it back').toBeFocused();
  expect(await activeOf(page)).toBe('div[data-part=user]');
  expect(posts, 'two posts were answered in the browser, and none reached the server').toBe(2);
});

/** P2: a row leaves while its Trace help holds focus: focus goes to the heading of the section the row left. */
test('P2: a row that leaves with its Trace help open gives focus to its section heading', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  await open(page);
  const text = unique('P2 reminder');
  const ref = `ZzFloorP2${Date.now().toString(36)}`;
  const dueAt = inMs(3_600_000);
  await applied(page, await publishReminder(user, { ref, text, dueAt, traceHeaderId: HEADER, traceNamespace: 'OCUTALON' }));
  const row = rowOf(page, text);
  const link = row.locator('app-trace-link a');
  await expect(link, 'the reminder row carries a Trace link').toHaveCount(1, { timeout: CARD_MS });

  await link.click();
  const help = page.getByRole('dialog', { name: 'Sign in to Visual Trace', exact: true });
  await expect(help, 'pressing the link shows the sign-in help').toBeVisible();
  await expect(help.locator(':focus'), 'with focus inside it').toHaveCount(1);

  await applied(page, await publishReminder(user, { ref, text, dueAt, state: 'fired' }));
  await expect(row, 'the row leaves in its own update').toHaveCount(0, { timeout: CARD_MS });
  await expect(help, 'and takes the help with it').toHaveCount(0);
  await expect(page.locator('#rail-heading-reminders'), 'focus is on the Reminders heading').toBeFocused();
  expect(await activeOf(page)).toBe('h3#rail-heading-reminders');
});

/** P3: the load error's Retry keeps focus when it fails again, and focus goes to the main region once the page has loaded. */
test('P3: the load error\'s Retry keeps focus when it fails and gives it to the main region when the page loads', async ({ page }) => {
  let answers = 0;
  const handler = async (route: Route): Promise<void> => {
    answers += 1;
    await route.fulfill({ status: 500, contentType: 'application/json', body: SERVER_ERROR });
  };
  await page.route(`**${STATE}`, handler);
  const { user, password } = fixtureUser(KIND);
  await signIn(page, user, password);
  const main = mainOf(page);
  await expect(main).toHaveAttribute('data-snapshot', 'failed', { timeout: CARD_MS });
  const retry = main.getByRole('button', { name: 'Retry', exact: true });
  await retry.focus();
  await expect(retry, 'Retry holds focus').toBeFocused();

  const failedAgain = page.waitForResponse((response) => new URL(response.url()).pathname === STATE, { timeout: CARD_MS });
  await page.keyboard.press('Enter');
  await failedAgain;
  await expect.poll(() => answers, { message: 'Retry asked for the snapshot again' }).toBe(2);
  await expect(retry, 'the failed Retry is restored').not.toHaveAttribute('aria-busy', 'true');
  await expect(main).toHaveAttribute('data-snapshot', 'failed');
  await expect(retry, 'and keeps focus').toBeFocused();

  await page.unroute(`**${STATE}`, handler);
  const answered = page.waitForResponse((response) => new URL(response.url()).pathname === STATE && response.status() === 200, { timeout: CARD_MS });
  await page.keyboard.press('Enter');
  await answered;
  await expect(main, 'the page loads').toHaveAttribute('data-snapshot', 'loaded', { timeout: CARD_MS });
  await expect(page.locator('.load-error'), 'the error leaves').toHaveCount(0);
  await expect(main, 'and focus is on the main region').toBeFocused();
  expect(await activeOf(page)).toBe('main');
});

/** P4: a reply, a card, a leaving row and a banner leave the composer's focus alone, and so does an update in place of a focused row. */
test('P4: nothing else moves focus: the composer and a focused row keep it while content arrives and changes', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const refs: string[] = [];
  let running: string | undefined;
  try {
    await publishStatus(user, { condition: 'resetSoon', active: false });
    const stamp = Date.now().toString(36);
    const production = `Zz.Floor.P4${stamp}`;
    const name = `zz P4 check ${stamp}`;
    const lastRunAt = inMs(-60_000);
    const check = await seedCheck(user, { namespace: 'OCUTALON', production, displayName: name, lastRunAt, result: 'passed', finding: '', lastRunHeaderId: HEADER });
    refs.push(check);
    await open(page);
    const checkRow = rowOf(page, name);
    await expect(checkRow, 'the check shows in the rail').toHaveCount(1);

    const seeded = await seedTurns(user, [{ createdAt: '2019-09-01T10:00:00Z', text: 'zz P4 question', replyText: '', state: 'running' }], true);
    running = seeded.refs[0]!;
    await expect(replyOf(page, running).locator('.indicator'), 'a turn is running').toBeVisible({ timeout: CARD_MS });
    const reminder = `ZzFloorP4${stamp}`;
    const reminderText = unique('P4 reminder');
    const dueAt = inMs(3_600_000);
    await applied(page, await publishReminder(user, { ref: reminder, text: reminderText, dueAt }));
    await expect(rowOf(page, reminderText), 'and a reminder is pending').toHaveCount(1);

    const field = composerOf(page);
    await field.focus();
    await expect(field, 'the composer holds focus').toBeFocused();
    await countFocusins(page);

    await finishTurn(user, running, 'zz P4 reply. More.');
    running = undefined;
    await expect(replyOf(page, seeded.refs[0]!).locator('.text'), 'a reply lands').toHaveText('zz P4 reply. More.', { timeout: CARD_MS });
    await expect(field).toBeFocused();

    const summary = unique('P4 tell now');
    const decisionRef = await seedDecision(user, { outcome: 'tellnow', summary, reasons: 'zz first.', confidence: 0.9, costUSD: 0.0003 });
    refs.push(decisionRef);
    await sendItemDecision(user, { outcome: 'tellnow', summary, decisionRef });
    await expect(page.locator('app-chat-panel app-notice-card').filter({ hasText: summary }), 'a tell-now card arrives').toHaveCount(1, { timeout: CARD_MS });
    await expect(field).toBeFocused();

    await applied(page, await publishReminder(user, { ref: reminder, text: reminderText, dueAt, state: 'fired' }));
    await expect(rowOf(page, reminderText), 'a rail row leaves').toHaveCount(0, { timeout: CARD_MS });
    await expect(field).toBeFocused();

    await applied(page, await publishStatus(user, { condition: 'resetSoon', active: true }));
    await expect(banner(page, 'resetSoon'), 'a banner appears').toHaveCount(1, { timeout: CARD_MS });
    await expect(field, 'and the composer still holds focus').toBeFocused();
    expect(await focusinCount(page), 'no focus moved at all').toBe(0);
    expect(await activeOf(page)).toBe('textarea#composer-field');

    const link = checkRow.locator('app-trace-link a');
    await link.focus();
    await expect(link, 'a check row\'s link holds focus').toBeFocused();
    await countFocusins(page);
    const finding = unique('P4 finding');
    await applied(page, await publishCheck(user, { ref: check, namespace: 'OCUTALON', production, displayName: name, lastRunAt: inMs(0), result: 'failed', finding, lastRunHeaderId: HEADER }));
    await expect(checkRow.locator('.meta'), 'the check is republished with a new result, in place').toContainText(finding, { timeout: CARD_MS });
    await expect(checkRow).toHaveCount(1);
    await expect(link, 'and focus is still on its row').toBeFocused();
    expect(await focusinCount(page), 'and moved nowhere in between').toBe(0);
  } finally {
    await publishStatus(user, { condition: 'resetSoon', active: false });
    if (running !== undefined) await finishTurn(user, running, 'zz P4 finished');
    await cleanFixtureRows(refs);
  }
});
