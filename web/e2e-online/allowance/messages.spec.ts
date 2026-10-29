import { expect, test, type Locator, type Page } from '@playwright/test';

import { post, sessionEvents, MESSAGES } from '../../e2e/support/api';
import { allowanceRow, epochOf, mailCounts, removeSession, seedAllowance, seedIncomingMail, signInFromSplash, signOutGroup, turnRowsOf } from '../support';

/**
 * Story 16.9, the session's message allowance and the simulated-email limit on the page (A1, A2, E1 and E2; matrix rows 1 to 3, 10 to 12 and
 * 17; AC 1, 3, 4 and 7). The project runs on its own online-demo throwaway with the message allowance at 50, the daily cap at $20 and the
 * runners' keys pointed at the CI mock. Every case signs out of the whole sign-in group and removes the rows it made in `finally`. The texts
 * are written out here, as the independent oracle of the page's own.
 * - A1: a new session sends 50 messages through the API (distinct clientIds, all 202) and types the 51st in the composer: the answer is 429
 *   allowance with retryAt and limit; the banner heads the stack, cannot be closed and opens the README's install section; the composer's
 *   field and Send and the guide's send prompt are aria-disabled and described by a visible reason that is the banner's text; the typed text
 *   is back in the field; a press of Send, Enter in the field and a click on the guide prompt post nothing; exactly one allowance notice
 *   card shows; a 52nd post gets a 429 and adds no second card; the refused Turn rows are in the state refused with no ClientId and none is
 *   queued; Break the feed's aria-disabled is what it was. The banner shows within 2 s of the 429, which only the page's own handling of the
 *   429 can do (the status event comes at the monitor's next run).
 * - A2: a new session whose rolling hour holds 50 entries about 3570 s old is refused its next message with a retryAt about 30 s ahead (about twice
 *   the status monitor's 15 s run, so that a run falls inside the window);
 *   within 45 s the banner clears, the controls return, its stream carries the allowance status with active false and a send gets 202.
 * - E1: 20 simulated emails through the API (samples and typed), then a chip press: 429 email_limit, the chips and Send are aria-disabled with
 *   the email text in page time, and no 21st row or mailbox event exists.
 * - E2: a new session with 20 incoming emails about 3580 s old: a form Send is refused, and within 45 s the chips and Send return and a press
 *   gets 202.
 */
test.describe.configure({ timeout: 240_000 });

const INSTALL = 'https://github.com/jbrandtmse/OcuTalon#install-it-yourself';
const USED_UP = /^You've used this session's 50 messages for the hour \(messages you send in the chat or Telegram\)\. You can send more at .+\.$/;
const CARD_TEXT = "You've used this session's 50 messages for the hour. You can send more at ";
const EMAIL_LIMIT = /^You've simulated 20 emails this hour\. You can send more at (.+)\.$/;

const mainOf = (page: Page): Locator => page.locator('main.main');
const composer = (page: Page): Locator => page.getByRole('textbox', { name: 'Message OcuTalon' });
const sendButton = (page: Page): Locator => page.locator('app-composer').getByRole('button', { name: 'Send', exact: true });
const guideSend = (page: Page): Locator => page.locator('app-demo-guide [data-guide-focus="action"]');
const breakFeed = (page: Page): Locator => page.locator('app-break-feed-box app-server-button button');
const banner = (page: Page): Locator => page.locator('[data-banner="allowance"]');
const cards = (page: Page): Locator => page.locator('app-notice-card').filter({ hasText: CARD_TEXT });
const chips = (page: Page): Locator => page.locator('app-simulated-mailbox .chips app-server-button button');
const formSend = (page: Page): Locator => page.locator('app-simulated-mailbox .actions app-server-button button');

/** Signs the demo account in at the page and returns its epoch, once the snapshot has loaded. */
async function open(page: Page): Promise<string> {
  await signInFromSplash(page);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  return epochOf(page);
}

/** The refusal that a post of the message answers: the response of the page's own POST to /messages with the status 429. */
function refusedPost(page: Page) {
  return page.waitForResponse((response) => response.url().includes('/api/v1/messages') && response.request().method() === 'POST' && response.status() === 429);
}

/** Opens the Simulated mailbox tab. */
async function openMailbox(page: Page): Promise<void> {
  await page.getByRole('tab', { name: /^Simulated mailbox/ }).click();
  await expect(chips(page), 'the three sample chips').toHaveCount(3);
}

/** The page time that the browser shows for a UTC time, as the page formats it (hour and minute, the browser's locale and zone). */
function pageTimeOf(page: Page, iso: string): Promise<string> {
  return page.evaluate((time) => new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(time)), iso);
}

test('A1: the 51st message is refused with a 429, the banner and the explained-disabled controls show, and one notice card follows', async ({ page }) => {
  let epoch = '';
  try {
    epoch = await open(page);
    const feedBefore = await breakFeed(page).getAttribute('aria-disabled');
    for (let i = 1; i <= 50; i += 1) {
      const answered = await post(page.request, MESSAGES, { clientId: `zz-a1-${epoch.slice(0, 6)}-${i}`, text: `zz message ${i}`, fromGuide: false });
      expect(answered.status(), `message ${i} is accepted`).toBe(202);
    }
    await composer(page).fill('zz the 51st');
    const refused = refusedPost(page);
    await sendButton(page).click();
    const answer = await refused;
    const body = (await answer.json()) as { error: { code: string; message: string }; retryAt: string; limit: number };
    expect(Object.keys(body), 'the 429 holds the error, retryAt and limit').toEqual(['error', 'retryAt', 'limit']);
    expect([body.error.code, body.limit], 'the code allowance and the limit 50').toEqual(['allowance', 50]);
    expect(Date.parse(body.retryAt), 'retryAt is ahead').toBeGreaterThan(Date.now());

    await expect(banner(page), "the allowance banner shows at once, from the page's own 429 (not from the next status event)").toBeVisible({ timeout: 2_000 });
    await expect(page.locator('[data-banner]').first(), 'and heads the stack').toHaveAttribute('data-banner', 'allowance');
    await expect(banner(page).locator('button'), 'it cannot be closed').toHaveCount(0);
    await expect(banner(page).getByRole('link'), 'its action opens the README\'s install section').toHaveAttribute('href', INSTALL);
    const text = (await banner(page).locator('.text').innerText()).trim();
    expect(text, "the banner's text").toMatch(USED_UP);

    const reason = page.locator('#composer-allowance-reason');
    await expect(reason, "the composer's reason is the banner's text").toHaveText(text);
    for (const control of [composer(page), sendButton(page)]) {
      await expect(control, 'the composer is aria-disabled, not disabled').toHaveAttribute('aria-disabled', 'true');
      await expect(control).toHaveAttribute('aria-describedby', 'composer-allowance-reason');
      await expect(control, 'and is not disabled, so it keeps its place in the tab order').not.toHaveAttribute('disabled', /.*/);
    }
    await expect(guideSend(page), "the guide's send prompt is aria-disabled and described by a reason").toHaveAttribute('aria-disabled', 'true');
    await expect(guideSend(page)).toHaveAttribute('aria-describedby', 'guide-allowance-reason');
    await expect(page.locator('#guide-allowance-reason'), "equal to the banner's text").toHaveText(text);
    await expect(composer(page), 'the typed text is back in the field').toHaveValue('zz the 51st');

    const posted: string[] = [];
    page.on('request', (request) => {
      if (request.method() === 'POST' && request.url().includes('/api/v1/messages')) posted.push(request.url());
    });
    await sendButton(page).click({ force: true });
    await composer(page).focus();
    await page.keyboard.press('Enter');
    await guideSend(page).click({ force: true });
    await page.waitForTimeout(1500);
    expect(posted, 'a press of Send, Enter in the field and a click on the guide prompt send nothing while the allowance is used up').toEqual([]);
    await expect(composer(page), 'and the typed text stays in the field').toHaveValue('zz the 51st');
    if (feedBefore === null) {
      await expect(breakFeed(page), "Break the feed's state is what it was: not disabled").not.toHaveAttribute('aria-disabled', /.*/);
    } else {
      await expect(breakFeed(page), "Break the feed's state is what it was").toHaveAttribute('aria-disabled', feedBefore);
    }

    await expect(cards(page), 'exactly one allowance notice card, with the install link').toHaveCount(1, { timeout: 30_000 });
    await expect(cards(page).first()).toContainText(INSTALL);
    await expect(cards(page).first()).toContainText(' ET, or install OcuTalon yourself to keep going: ');

    const asked = Date.now();
    const again = await post(page.request, MESSAGES, { clientId: `zz-a1-${epoch.slice(0, 6)}-52`, text: 'zz the 52nd', fromGuide: false });
    process.stdout.write(`MEASURED Story 16.9 Task 0 (b): the 429 round trip of the 52nd post took ${Date.now() - asked} ms\n`);
    expect(again.status(), 'a 52nd post through the API').toBe(429);
    expect(((await again.json()) as { error: { code: string } }).error.code).toBe('allowance');
    await page.waitForTimeout(6000);
    await expect(cards(page), 'adds no second card').toHaveCount(1);

    const turns = await turnRowsOf(epoch);
    const refusedTurns = turns.filter((turn) => turn.state === 'refused');
    expect(refusedTurns.map((turn) => turn.text), 'two refused Turn rows').toEqual(['zz the 51st', 'zz the 52nd']);
    expect(refusedTurns.map((turn) => turn.clientId), 'with no ClientId').toEqual(['', '']);
    expect(turns.filter((turn) => /^zz the 5[12]/.test(turn.text) && turn.state !== 'refused'), 'and none of them is queued or done').toEqual([]);
    expect((await allowanceRow(epoch)).until, 'the row holds the window').toBe(body.retryAt);
  } finally {
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});

test('A2: the allowance window clears at retryAt on the page and in the status stream, and a send is accepted again', async ({ page }) => {
  let epoch = '';
  try {
    epoch = await open(page);
    await seedAllowance(epoch, 50, 3570);
    await composer(page).fill('zz refused for twenty seconds');
    const refused = refusedPost(page);
    await sendButton(page).click();
    const body = (await (await refused).json()) as { retryAt: string; limit: number };
    const ahead = (Date.parse(body.retryAt) - Date.now()) / 1000;
    expect(ahead, `retryAt is about 30 s ahead (${ahead.toFixed(1)} s)`).toBeGreaterThan(5);
    expect(ahead).toBeLessThan(40);
    await expect(banner(page), "the banner shows at once, from the page's own 429").toBeVisible({ timeout: 2_000 });
    await expect(sendButton(page)).toHaveAttribute('aria-disabled', 'true');

    await expect(banner(page), 'within 45 s the banner clears').toHaveCount(0, { timeout: 45_000 });
    await expect(sendButton(page), 'the controls return').not.toHaveAttribute('aria-disabled', 'true');
    await expect(composer(page)).not.toHaveAttribute('aria-disabled', 'true');
    await expect(guideSend(page)).not.toHaveAttribute('aria-disabled', 'true');
    await expect(page.locator('#composer-allowance-reason')).toHaveCount(0);

    const events = await sessionEvents(
      page.request,
      0,
      (found) => found.some((event) => event.type === 'status' && event.payload['condition'] === 'allowance' && event.payload['active'] === false),
      45,
    );
    const statuses = events.filter((event) => event.type === 'status' && event.payload['condition'] === 'allowance');
    expect(statuses.map((event) => event.payload['active']), 'the stream carries the allowance opening and its clear').toEqual([true, false]);
    expect(statuses[1]?.payload['slots'], 'the clear has no slots').toBeUndefined();
    const sent = await post(page.request, MESSAGES, { clientId: `zz-a2-${epoch.slice(0, 6)}`, text: 'zz sent again', fromGuide: false });
    expect(sent.status(), 'a send is accepted').toBe(202);
  } finally {
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});

test('E1: the 21st simulated email is refused, and the chips and Send are explained-disabled until retryAt', async ({ page }) => {
  let epoch = '';
  try {
    epoch = await open(page);
    for (let i = 1; i <= 20; i += 1) {
      const answered =
        i % 2 === 0
          ? await post(page.request, '/ocutalon/api/v1/mailbox/samples/newsletter', {})
          : await post(page.request, '/ocutalon/api/v1/mailbox/incoming', { from: 'zz Dana <dana@example.com>', subject: `zz email ${i}`, body: 'zz body' });
      expect(answered.status(), `email ${i} is accepted`).toBe(202);
    }
    await openMailbox(page);
    const refused = page.waitForResponse((response) => response.url().includes('/api/v1/mailbox/samples/') && response.status() === 429);
    await chips(page).first().click();
    const body = (await (await refused).json()) as { error: { code: string }; retryAt: string };
    expect(Object.keys(body), 'the 429 holds the error and retryAt').toEqual(['error', 'retryAt']);
    expect(body.error.code).toBe('email_limit');

    const reason = page.locator('#mailbox-email-limit');
    await expect(reason, 'the reason shows').toBeVisible();
    const text = (await reason.innerText()).trim();
    const match = EMAIL_LIMIT.exec(text);
    expect(match, `the email text: ${text}`).not.toBeNull();
    expect(match?.[1], 'with the time as a page time').toBe(await pageTimeOf(page, body.retryAt));
    await expect(chips(page)).toHaveCount(3);
    for (let i = 0; i < 3; i += 1) {
      await expect(chips(page).nth(i), `chip ${i + 1} is aria-disabled and described by the reason`).toHaveAttribute('aria-disabled', 'true');
      await expect(chips(page).nth(i)).toHaveAttribute('aria-describedby', 'mailbox-email-limit');
    }
    await page.getByRole('button', { name: 'Simulate an incoming email' }).click();
    await expect(formSend(page), 'the form\'s Send is aria-disabled too').toHaveAttribute('aria-disabled', 'true');
    await expect(formSend(page)).toHaveAttribute('aria-describedby', 'mailbox-email-limit');

    const counts = await mailCounts(epoch);
    expect(counts, 'no 21st row and no 21st mailbox event exists').toEqual({ rows: 20, events: 20 });
  } finally {
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});

test('E2: a refused form Send is allowed again at retryAt, and the chips and Send return', async ({ page }) => {
  let epoch = '';
  try {
    epoch = await open(page);
    await seedIncomingMail(epoch, 20, 3580);
    await openMailbox(page);
    await page.getByRole('button', { name: 'Simulate an incoming email' }).click();
    await page.getByLabel('Subject', { exact: true }).fill('zz refused email');
    await page.getByLabel('Body', { exact: true }).fill('zz body');
    const refused = page.waitForResponse((response) => response.url().includes('/api/v1/mailbox/incoming') && response.status() === 429);
    await formSend(page).click();
    const body = (await (await refused).json()) as { retryAt: string };
    const ahead = (Date.parse(body.retryAt) - Date.now()) / 1000;
    expect(ahead, `retryAt is about 20 s ahead (${ahead.toFixed(1)} s)`).toBeGreaterThan(5);
    expect(ahead).toBeLessThan(40);
    await expect(formSend(page)).toHaveAttribute('aria-disabled', 'true');
    await expect(chips(page).first()).toHaveAttribute('aria-disabled', 'true');

    await expect(page.locator('#mailbox-email-limit'), 'within 45 s the reason clears').toHaveCount(0, { timeout: 45_000 });
    await expect(chips(page).first(), 'the chips return').not.toHaveAttribute('aria-disabled', 'true');
    await expect(formSend(page), 'and Send').not.toHaveAttribute('aria-disabled', 'true');
    const accepted = page.waitForResponse((response) => response.url().includes('/api/v1/mailbox/samples/') && response.request().method() === 'POST');
    await chips(page).first().click();
    expect((await accepted).status(), 'a press is accepted').toBe(202);
  } finally {
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});
