import { expect, test, type BrowserContext, type Locator, type Page } from '@playwright/test';

import { EVENTS, MESSAGES, STATE } from '../e2e/support/api';
import { loadedAfter } from '../e2e/support/floor';
import { announcements, recordAnnouncements } from '../e2e/support/page';
import { postTurn, type Cursor, type Turn } from '../e2e/support/trace';
import { BUSY_HEADER, DEMO_BUSY_TEXT, httpConnections, publicValue, readStatus, removeSession, setPublic, signInFromSplash, signInOverHttpFrom, signOutGroup, SIGN_OUT } from './support';

/**
 * Story 16.5, the demo's busy state on the page (B1 to B3; matrix rows 7 and 9 to 12). The project runs on the online-demo throwaway, with
 * the connection cap at its start value and the reserve at 2. Nothing is proxied here (the unit's proxied phase runs address-limit.spec.ts
 * alone), so every sign-in is exempt from the busy refusal. Every case signs out of the whole sign-in group and removes the rows it made
 * in `finally`; B1, which lowers `connectionCap`, restores it there and reads it back.
 * - B1: page P signs in from the splash and makes a turn, session S2 signs in over HTTP, and B1 sets the cap from a reading of the HTTP
 *   view of the connections so that the status is busy with these two sessions signed in. A CSP session is not counted in the connections
 *   on build 154 (Task 0 (b)), so the cap alone carries the state and "a place is free" is a cap one higher, set after S2 signs out. The
 *   status says busy with the marker header, in its plain and in its trace form (Story 29.7: fewer than 6 visitors, so the
 *   connections alone make both busy; with the cap one higher both are free); a
 *   third sign-in over HTTP is let in (row 7) and signed out at once; a fresh splash shows the busy error with the link, focused, with
 *   the button enabled; P types "draft text" and presses "Open my conversation in Visual Trace": no tab opens, the "Demo busy" banner
 *   shows with the README action and the composer keeps the text. When S2 signs out the banner clears within 15 s, and the next press
 *   opens the link's trace page.
 * - B2: a message that the server refuses with 503 comes back to an empty composer with no "Not sent" and no announcement, the banner shows
 *   while the 503s last and clears at the first 2xx poll, and Send then posts the text; with other text already in the composer the message
 *   stays as "Not sent" with Retry sending (today's failure).
 * - B2b (DW-252): the guide's prompt button, pressed while the server refuses its post with 503, leaves no entry behind: no bubble, no "Not
 *   sent", no Retry sending, an empty composer and no announcement, and the "Demo busy" banner shows, as in B2.
 * - B3: a reply's Trace link, pressed while the status says busy, opens nothing and shows the banner; the check asks the status in its
 *   trace form, with exactly the keys for (trace) and t (a unique time), and so does every quiet re-check; a quiet re-check that fails
 *   keeps the banner, and the real status clears it.
 * - B3b: the same press while the status check fails (an answer that is not JSON) opens the tab and shows no banner.
 * - B3c: the same press while the status never answers opens the tab within the click's activation, and shows no banner.
 * The file runs in full Chromium with its popup blocker on (Playwright's default launch turns the blocker off, and its headless shell has
 * none), so a window that the page opens after the click's activation has run out is blocked, as in a visitor's browser.
 * The texts are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 240_000 });
test.skip(process.env['OCUTALON_ONLINE_PROXIED'] === '1', 'runs in the browser step, where nothing is proxied');
test.use({ channel: 'chromium', launchOptions: { ignoreDefaultArgs: ['--disable-popup-blocking'] } });

const README = 'https://github.com/jbrandtmse/OcuTalon#readme';
const INSTALL = 'https://github.com/jbrandtmse/OcuTalon#install-it-yourself';
const CONVERSATION_NAME = 'Open my conversation in Visual Trace (opens in a new tab)';
const TRACE_NAME = 'Trace (opens in a new tab)';
const BANNER = '[data-banner="demoBusy"]';

const composer = (page: Page): Locator => page.getByRole('textbox', { name: 'Message OcuTalon' });
const guideSend = (page: Page): Locator => page.locator('app-demo-guide [data-guide-focus="action"]');
const traceMenu = (page: Page): Locator => page.getByRole('button', { name: 'Visual Trace', exact: true });
const refusal = { error: { code: 'busy', message: 'Something went wrong inside OcuTalon. Try again.' } };

/** Signs the demo account in at the page and waits for the loaded snapshot (loadedAfter); its epoch and a cursor at the end of its session stream. */
async function open(page: Page): Promise<{ epoch: string; cursor: Cursor }> {
  await loadedAfter(page, () => signInFromSplash(page));
  const state = (await (await page.request.get(STATE)).json()) as { epoch: string; streams: { session: number } };
  return { epoch: state.epoch, cursor: { seq: state.streams.session } };
}

/** The pages that the context opens from now on. */
function watchPages(context: BrowserContext): () => Page[] {
  const opened: Page[] = [];
  context.on('page', (page) => opened.push(page));
  return () => opened;
}

/** The trace page of a turn is at the turn's traceUrl (its path and session). */
async function expectAtTrace(popup: Page, turn: Turn, label: string): Promise<void> {
  const want = new URL(turn.traceUrl, 'http://stack.invalid');
  await expect.poll(() => new URL(popup.url()).pathname, { message: `${label}: the tab is at the link's page`, timeout: 30_000 }).toBe(want.pathname);
  expect(new URL(popup.url()).searchParams.get('SESSIONID'), `${label}: and at the link's session`).toBe(want.searchParams.get('SESSIONID'));
}

/** The page's trace check asks the status with exactly the keys for (trace) and t (a time in milliseconds, so that no cache answers). */
function expectTraceQuery(check: URL, label: string): void {
  expect([...check.searchParams.keys()], `${label}: the query holds exactly for and t`).toEqual(['for', 't']);
  expect(check.searchParams.get('for'), `${label}: for is trace`).toBe('trace');
  expect(check.searchParams.get('t'), `${label}: t is a time in milliseconds`).toMatch(/^\d{13}$/);
}

/** The banner shows the busy text, with the README action that opens a new tab. */
async function expectBanner(page: Page, label: string): Promise<void> {
  const banner = page.locator(BANNER);
  await expect(banner, `${label}: the Demo busy banner shows`).toHaveCount(1);
  await expect(banner.locator('.text'), `${label}: with the busy text`).toHaveText(DEMO_BUSY_TEXT);
  const action = banner.getByRole('link', { name: 'Install it yourself (opens in a new tab)', exact: true });
  await expect(action, `${label}: and the README action, to its install section`).toHaveAttribute('href', INSTALL);
  await expect(action).toHaveAttribute('target', '_blank');
}

test('B1: with the demo busy, a trace press shows the banner and opens nothing, until a place is free', async ({ browser, context, page, playwright }) => {
  const savedCap = await publicValue('connectionCap');
  const status = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  const epochs: string[] = [];
  const others: Array<{ dispose: () => Promise<void>; get: (path: string) => Promise<unknown> }> = [];
  const fresh = await browser.newContext();
  try {
    await recordAnnouncements(page);
    const { epoch, cursor } = await open(page);
    epochs.push(epoch);
    const turn = await postTurn(page.request, cursor, 1, 'online-busy');

    const second = await signInOverHttpFrom(playwright, '203.0.113.211');
    others.push(second.api);
    expect(second.answer.status(), 'S2 signs in over HTTP').toBe(200);
    const stateTwo = await second.api.get(STATE);
    expect(stateTwo.status(), 'S2 has a session').toBe(200);
    epochs.push(((await stateTwo.json()) as { epoch: string }).epoch);

    const reserve = Number(await publicValue('connectionReserve'));
    const view = await httpConnections(status);
    console.log(`MEASURED B1: the HTTP view of the connections with P and S2 signed in is ${view} (reserve ${reserve})`);
    await setPublic('connectionCap', String(view + reserve));
    const busy = await readStatus(status);
    expect(busy, 'the status is busy with exactly P and S2, with the marker header and the status code 200').toEqual({ busy: true, header: '1', code: 200 });
    // Story 29.7, row 8: the trace form is busy from the connections too, with fewer than 6 visitors, and has the same header and code.
    expect(await readStatus(status, 'trace'), 'the trace form is busy as well, with the marker header and the status code 200').toEqual({ busy: true, header: '1', code: 200 });

    // Row 7: a request that is not proxied is exempt. The status is busy, where a proxied sign-in is refused (the unit's row 5), so only the
    // exemption lets the third sign-in in; it is signed out at once.
    const third = await signInOverHttpFrom(playwright, '203.0.113.212');
    others.push(third.api);
    try {
      expect(third.answer.status(), 'a third sign-in over HTTP while busy answers 200').toBe(200);
      expect(await third.answer.text(), 'and gets the shell, not the splash').toContain('<app-root');
      const stateThree = await third.api.get(STATE);
      expect(stateThree.status(), 'it has a session').toBe(200);
      epochs.push(((await stateThree.json()) as { epoch: string }).epoch);
    } finally {
      await third.api.get(SIGN_OUT).catch(() => undefined);
    }
    await expect.poll(async () => (await readStatus(status)).busy, { message: 'the demo is busy again with P and S2 once S3 has signed out', timeout: 30_000 }).toBe(true);

    // Row 9: the splash of a fresh context.
    const splash = await fresh.newPage();
    const answered = await splash.goto(`/ocutalon/?probe=${Date.now()}b1`);
    expect(answered?.headers()[BUSY_HEADER], 'the busy splash carries the marker header').toBe('1');
    expect(answered?.status(), 'with the status code 200').toBe(200);
    const error = splash.locator('#ocu-error');
    await expect(error, 'the splash shows the busy error').toContainText(DEMO_BUSY_TEXT);
    const link = error.getByRole('link', { name: 'Install it yourself (README) (opens in a new tab)', exact: true });
    await expect(link, 'with the README link').toHaveAttribute('href', README);
    expect(await splash.evaluate(() => document.activeElement?.id), 'the error has the focus').toBe('ocu-error');
    await expect(splash.getByRole('button', { name: 'Sign in and start', exact: true }), 'the button is enabled').toBeEnabled();
    await expect(splash.getByLabel('User name', { exact: true }), 'no field is marked').not.toHaveAttribute('aria-invalid', /.*/);
    await expect(splash.getByLabel('Password', { exact: true })).not.toHaveAttribute('aria-invalid', /.*/);
    await signOutGroup(fresh);
    await fresh.close();

    // P presses "Open my conversation in Visual Trace".
    const opened = watchPages(context);
    await composer(page).fill('draft text');
    await traceMenu(page).click();
    const menu = page.getByRole('dialog', { name: 'Visual Trace', exact: true });
    const conversation = menu.getByRole('link', { name: CONVERSATION_NAME, exact: true });
    await expect(conversation).toHaveAttribute('href', turn.traceUrl);
    await conversation.click();
    await expect(menu, 'the Visual Trace menu closes, as it does today').toBeHidden();
    await expectBanner(page, 'after the press');
    await page.waitForTimeout(3000);
    expect(opened().length, 'no new page opens within 3 s of the press').toBe(0);
    await expect(composer(page), 'the composer still holds what was typed').toHaveValue('draft text');
    expect(await announcements(page, DEMO_BUSY_TEXT), 'the banner is announced once').toBe(1);

    // A place is free: S2 signs out (a session is not counted on this stack, Task 0 (b)), the cap is one higher, and the page's quiet re-check
    // clears the banner.
    await second.api.get(SIGN_OUT);
    await setPublic('connectionCap', String(view + reserve + 1));
    expect((await readStatus(status)).busy, 'the status is no longer busy').toBe(false);
    expect((await readStatus(status, 'trace')).busy, 'nor is the trace form').toBe(false);
    await expect(page.locator(BANNER), 'the banner clears within 15 s of a place being free').toHaveCount(0, { timeout: 15_000 });
    await traceMenu(page).click();
    const [popup] = await Promise.all([context.waitForEvent('page'), conversation.click()]);
    await expectAtTrace(popup, turn, 'the next press');
    console.log('MEASURED Task 0 (e): Chromium, with its popup blocker on, opened the window that window.open asked for after the awaited status check');
    await popup.close();
  } finally {
    await signOutGroup(page);
    await signOutGroup(fresh).catch(() => undefined);
    for (const api of others) {
      await api.get(SIGN_OUT).catch(() => undefined);
      await api.dispose().catch(() => undefined);
    }
    await status.dispose();
    await fresh.close().catch(() => undefined);
    await setPublic('connectionCap', savedCap);
    for (const epoch of epochs) await removeSession(epoch);
  }
});

test('B2: a message refused with 503 comes back to the composer, and stays as Not sent when the composer holds other text', async ({ page }) => {
  let epoch = '';
  try {
    await recordAnnouncements(page);
    ({ epoch } = await open(page));
    const field = composer(page);

    // Row 11: the 503 of a post and two 503 polls.
    let polls = 0;
    await page.route(`**${EVENTS}*`, async (route) => {
      polls += 1;
      await route.fulfill({ status: 503, json: refusal });
    });
    let refused = 0;
    const post = async (route: import('@playwright/test').Route): Promise<void> => {
      if (refused === 0) {
        refused += 1;
        await route.fulfill({ status: 503, json: refusal });
        return;
      }
      await route.continue();
    };
    await page.route(`**${MESSAGES}`, post);
    await field.fill('busy check');
    await field.press('Enter');
    await expect.poll(() => refused, { message: 'the post was answered with 503' }).toBe(1);
    await expect(field, 'the composer holds the text again').toHaveValue('busy check');
    await expect(page.locator('app-chat-panel .failed'), 'no "Not sent"').toHaveCount(0);
    await expect(page.locator('app-chat-panel .bubble').filter({ hasText: 'busy check' }), 'and no entry in the chat').toHaveCount(0);
    await expectBanner(page, 'after the 503');
    const seen = polls;
    await expect.poll(() => polls, { message: 'two more polls are answered with 503', timeout: 30_000 }).toBeGreaterThanOrEqual(seen + 2);
    await expect(page.locator(BANNER), 'the banner shows while the 503s last').toHaveCount(1);
    expect(await announcements(page, 'Message not sent'), 'nothing says "Message not sent"').toBe(0);
    await page.unroute(`**${EVENTS}*`);
    await page.unroute(`**${MESSAGES}`, post);
    await expect(page.locator(BANNER), 'the banner clears at the first 2xx poll').toHaveCount(0, { timeout: 15_000 });
    await expect(field, 'the text is still there').toHaveValue('busy check');
    await field.press('Enter');
    await expect(page.locator('app-chat-panel .bubble').filter({ hasText: 'busy check' }), 'Send posts the text and it appears in the chat').toHaveCount(1);
    await expect(page.locator('app-chat-panel [data-part="reply"]'), 'its turn runs on, so it never lands in a later case').toHaveCount(1, { timeout: 30_000 });
    await expect(page.locator('app-chat-panel .failed')).toHaveCount(0);

    // Row 12: the composer already holds other text when the 503 comes.
    let release: () => void = () => undefined;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    let reached = 0;
    await page.route(`**${MESSAGES}`, async (route) => {
      reached += 1;
      await held;
      await route.fulfill({ status: 503, json: refusal });
    });
    await field.fill('first text');
    await field.press('Enter');
    await expect.poll(() => reached, { message: 'the post is held' }).toBe(1);
    await field.fill('newer text');
    release();
    await expect(page.locator('app-chat-panel .failed'), 'the message stays as Not sent').toHaveText('Not sent');
    await expect(page.getByRole('button', { name: 'Retry sending' }), 'with Retry sending').toHaveCount(1);
    await expect(field, 'the composer keeps the newer text').toHaveValue('newer text');
    await expect(page.locator('app-chat-panel .bubble').filter({ hasText: 'first text' })).toHaveCount(1);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

test('B2b: the guide prompt refused with 503 leaves the chat with no Not sent, an empty composer and the busy banner', async ({ page }) => {
  let epoch = '';
  try {
    await recordAnnouncements(page);
    ({ epoch } = await open(page));
    await expect(guideSend(page), "the guide's prompt button is usable").not.toHaveAttribute('aria-disabled', 'true');
    const bubbles = page.locator('app-chat-panel .bubble');
    const before = await bubbles.count();

    await page.route(`**${EVENTS}*`, async (route) => {
      await route.fulfill({ status: 503, json: refusal });
    });
    let refused = 0;
    const post = async (route: import('@playwright/test').Route): Promise<void> => {
      if (refused === 0) {
        refused += 1;
        await route.fulfill({ status: 503, json: refusal });
        return;
      }
      await route.continue();
    };
    await page.route(`**${MESSAGES}`, post);
    await guideSend(page).click();
    await expect.poll(() => refused, { message: "the prompt's post was answered with 503" }).toBe(1);
    await expectBanner(page, 'after the 503');
    await expect(bubbles, "the prompt's entry has left the chat").toHaveCount(before);
    await expect(page.locator('app-chat-panel .failed'), 'with no "Not sent"').toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Retry sending' }), 'and no Retry sending').toHaveCount(0);
    await expect(composer(page), "the composer holds nothing: the prompt's text did not move into it").toHaveValue('');
    expect(await announcements(page, 'Message not sent'), 'nothing says "Message not sent"').toBe(0);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

test('B3: a reply\'s Trace link pressed while the status says busy opens nothing and shows the banner', async ({ context, page }) => {
  let epoch = '';
  try {
    const signedIn = await open(page);
    epoch = signedIn.epoch;
    const turn = await postTurn(page.request, signedIn.cursor, 1, 'online-busy');
    const link = page.locator(`app-chat-panel [data-part="reply"][data-key="${turn.clientId}"] app-decision-strip app-trace-link a`);
    await expect(link, 'the turn has its Trace link').toHaveCount(1, { timeout: 30_000 });
    await expect(link).toHaveAccessibleName(TRACE_NAME);
    const opened = watchPages(context);
    const asked: string[] = [];
    await page.route('**/ocutalon/public/status*', async (route) => {
      asked.push(route.request().url());
      await route.fulfill({ status: 200, headers: { 'X-OcuTalon-Busy': '1' }, json: { ready: true, nextReset: null, busy: true, lastReset: null, lastResetKind: null } });
    });
    await link.click();
    await expectBanner(page, 'after the press');
    const check = new URL(asked[0] ?? 'http://stack.invalid/none');
    expect(check.pathname, 'the press asks the public status').toBe('/ocutalon/public/status');
    expectTraceQuery(check, 'the press');
    await page.waitForTimeout(3000);
    expect(opened().length, 'no new page opens within 3 s of the press').toBe(0);

    // A quiet re-check that fails (no answer it can read) does not say the demo is free: the banner stays and the next re-check is armed.
    await page.unroute('**/ocutalon/public/status*');
    const rechecks: string[] = [];
    await page.route('**/ocutalon/public/status*', async (route) => {
      rechecks.push(route.request().url());
      await route.abort();
    });
    await expect.poll(() => rechecks.length, { message: 'two quiet re-checks fail, the second armed by the first', timeout: 30_000 }).toBeGreaterThanOrEqual(2);
    for (const url of rechecks) expectTraceQuery(new URL(url), 'a quiet re-check');
    await expect(page.locator(BANNER), 'the banner stays through a failed re-check').toHaveCount(1);
    await page.unroute('**/ocutalon/public/status*');
    await expect(page.locator(BANNER), 'with the real status, the quiet re-check clears the banner').toHaveCount(0, { timeout: 25_000 });
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

test('B3b: a reply\'s Trace link pressed while the status check fails opens the tab and shows no banner', async ({ context, page }) => {
  let epoch = '';
  try {
    const signedIn = await open(page);
    epoch = signedIn.epoch;
    const turn = await postTurn(page.request, signedIn.cursor, 1, 'online-busy-open');
    const link = page.locator(`app-chat-panel [data-part="reply"][data-key="${turn.clientId}"] app-decision-strip app-trace-link a`);
    await expect(link, 'the turn has its Trace link').toHaveCount(1, { timeout: 30_000 });
    const opened = watchPages(context);
    await page.route('**/ocutalon/public/status*', async (route) => {
      await route.fulfill({ status: 200, contentType: 'text/html', body: '<html><body>not the status</body></html>' });
    });
    await link.click();
    await expect.poll(() => opened().length, { message: 'a status answer that is not JSON opens the tab', timeout: 15_000 }).toBe(1);
    await expectAtTrace(opened()[0]!, turn, 'after the failed check');
    await opened()[0]!.close();
    await expect(page.locator(BANNER), 'and shows no banner').toHaveCount(0);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

test('B3c: a reply\'s Trace link pressed while the status never answers opens the tab within the click\'s activation, and shows no banner', async ({ context, page }) => {
  let epoch = '';
  try {
    const signedIn = await open(page);
    epoch = signedIn.epoch;
    const turn = await postTurn(page.request, signedIn.cursor, 1, 'online-busy-silent');
    const link = page.locator(`app-chat-panel [data-part="reply"][data-key="${turn.clientId}"] app-decision-strip app-trace-link a`);
    await expect(link, 'the turn has its Trace link').toHaveCount(1, { timeout: 30_000 });
    const opened = watchPages(context);
    let asked = 0;
    await page.route('**/ocutalon/public/status*', () => {
      asked += 1;
    });
    await link.click();
    await expect.poll(() => asked, { message: 'the press asks the status, which never answers' }).toBe(1);
    await expect.poll(() => opened().length, { message: 'the check gives up while the click still allows a window, and the tab opens', timeout: 15_000 }).toBe(1);
    await expectAtTrace(opened()[0]!, turn, 'after the silent check');
    await opened()[0]!.close();
    await expect(page.locator(BANNER), 'and shows no banner').toHaveCount(0);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});
