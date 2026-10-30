import { expect, test, type Page, type Request, type Route } from '@playwright/test';

import { pageTime } from '../src/app/chat/page-time';
import { EVENTS, STATE, type LiveEvent } from '../e2e/support/api';
import { freeze, pageNow, recordTraffic, runUntil } from '../e2e/support/clock';
import { chk, irisScript } from '../e2e/support/iris';
import { announcements, recordAnnouncements } from '../e2e/support/page';
import { publicValue, recordSplashAnnouncements, removeSession, setPublic, signInFromSplash, signOutGroup, splashAnnouncements } from './support';

/**
 * Story 16.8, the page counts down to the reset and waits it out (matrix rows 13 and 14). The project runs on the online-demo throwaway,
 * whose reset anchor is two hours ahead of the unit's start, so that no real reset falls inside the run. Every case signs out of the whole
 * sign-in group and removes the rows it made in `finally`; R2 changes the anchor and puts it back, reading it back.
 * - R1 (row 13, AC 2 to 5): the last ten minutes before a reset on a controlled clock and controlled answers. The browser clock is
 *   installed at T - 10:30, where T is the stack's lastReset (read from IRIS: the reset that the real splash then names), and the page's
 *   /state answers nextReset T (any real resetSoon removed), its /events answers carry no real reset or resetSoon event, and one resetSoon
 *   event once the clock passes T - 5:00; /ocutalon/public/status answers the maintenance page's HTML, then not ready, then ready with an
 *   old last reset, then ready with last reset T. The pill reads "in 10 min" and turns urgent at T - 10:00; the banner appears after
 *   T - 5:00 in the catalog's order and is announced once; the last minute ticks every second while the pill's accessible text stays
 *   "in 1 minute"; at T the page shows the resetting view (texts, the 320px logo, the tab title, no header, no banners) and makes no
 *   request to /ocutalon/api/; with the CSP session ended the page goes once, on the answer with
 *   last reset T, to /ocutalon/?since=<its load time>, where the real splash shows the reset notice above both cards.
 * - R2 (row 14, AC 1 to 3): on the real clock, the anchor four minutes ahead: /state, the public status and the anchor agree on the next
 *   reset, /state's status holds resetSoon, the pill is urgent, the banner shows, and a fresh browser's splash shows the reset-soon notice
 *   under the sign-in card's title, not hidden, from which signing in still opens the page.
 * - R3 (row 11, AC 4): a 401 at or after the pending reset enters the resetting view and does not take the signed-out path. The page's
 *   wall clock jumps past the reset while its timers stay where they were, and /state and /events then answer 401.
 * - R3b (row 11, AC 4): lost contact past the pending reset enters the view: the same jump of the wall clock, with the API refusing calls.
 * - R3c (row 11, AC 4): an answer of the live path past the pending reset enters the view: the same jump, with the API answering.
 * - R4 (row 11, AC 2): a reset event that moves the next reset later, while more than five minutes remain, moves the pill.
 * - R5 (row 7, AC 3): the splash's script shows the reset-soon notice when the reset comes within five minutes, announces it once and
 *   hides it after the reset; the server wrote it hidden.
 * - R6 (row 11, AC 4): a 401 before the pending reset is not the reset's. On the online demo it takes the page back to the splash with
 *   the time the page loaded, with no signedOut=1 (Story 16.4), and the page never enters the resetting view.
 * - R7 (AC 4): the resetting view shows the logo of the page's theme, the light one in a light scheme and the dark one in a dark scheme,
 *   and follows the scheme when it changes.
 * - R8 (AC 2): the pill sits in the header's right group after the Status button (drawer band) and before the Visual Trace button, and the
 *   header still fits the window with it at 1024px and at 640px.
 * - R9 (row 13, AC 4, Task 0 (c)): the resetting view asks the public status with no cookie, while the signed-in page's own request
 *   carries the session; both are real requests that no route answers, so their headers are the network's.
 * Task 0 (a), (b), (c) and the unit's time print MEASURED lines. The texts are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 240_000 });
test.skip(process.env['OCUTALON_ONLINE_PROXIED'] === '1', 'runs in the browser step, where nothing is proxied');
test.use({ timezoneId: 'Asia/Kolkata', locale: 'en-GB' });

const RESET_BANNER = 'The demo resets in 5 minutes. Your session and Telegram pairing will be cleared.';
const HEADING = 'The demo is resetting.';
const BODY = 'It usually takes a few minutes. This page returns to the sign-in screen by itself.';
const TITLE = 'Resetting \u00b7 OcuTalon';
const RESET_NOTICE = (time: string): string => `The demo was reset at ${time}, which cleared your session. Sign in again for a fresh one.`;
const RESTART_NOTICE = 'The demo was restarted, which cleared your session. Sign in again for a fresh one.';
const SOON_NOTICE = /^The demo resets in (3|4) min, which may cut your run short\. You can start now or come back after \d{1,2}:\d{2}\.$/;
const STATUS = '/ocutalon/public/status';
/**
 * The idle cap that a case's /state answers carry (Story 16.4): the cases whose page clock runs past 600 s with no key press or click would
 * otherwise leave for the splash at the cap, so their snapshot raises it far above the case's longest run.
 */
const KEEP_ACTIVE_SECONDS = 86_400;
const EVENTS_POLL = /\/ocutalon\/api\/v1\/events\?/;

const mainOf = (page: Page) => page.locator('main.main');
const pill = (page: Page) => page.locator('app-reset-countdown .reset-countdown');
const pillShown = (page: Page) => pill(page).locator('span[aria-hidden="true"]');
const pillSpoken = (page: Page) => pill(page).locator('.visually-hidden');
const bannerIds = (page: Page): Promise<string[]> => page.evaluate(() => [...document.querySelectorAll('.banner-slot [data-banner]')].map((el) => el.getAttribute('data-banner') ?? ''));

const iso = (ms: number): string => `${new Date(ms).toISOString().slice(0, 19)}Z`;
const dateNow = (page: Page): Promise<number> => page.evaluate(() => Date.now());

/**
 * Moves the page's clock to a Date.now() value, a step of at most a second at a time (runUntil), so that the page handles its polls on the
 * way, and then 20 ms further: the page renders on the frame or timer that its change detection asks for, which the paused clock fires
 * only when it moves.
 */
async function runTo(page: Page, target: number): Promise<void> {
  for (let round = 0; round < 5; round += 1) {
    const left = target - (await dateNow(page));
    if (left <= 0) {
      await page.clock.runFor(20);
      return;
    }
    await runUntil(page, await pageNow(page), Math.min(left, 500_000));
  }
  throw new Error(`the page's clock did not reach ${iso(target)}`);
}

/** The first line of the answer: the stack's current time, UTC to the second. */
async function stackNow(): Promise<number> {
  const lines = await irisScript('Write !,"CHK|now|",$Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"');
  const now = Date.parse(chk(lines, 'now') ?? '');
  if (Number.isNaN(now)) throw new Error('the stack gave no time');
  return now;
}

/** R1: the last ten minutes before a reset, on a controlled clock and controlled answers. */
test('R1: the pill turns urgent at 10 minutes, the banner comes at 5, the resetting view shows at the reset and the page lands once on the splash with the reset notice', async ({ page, request }) => {
  let epoch = '';
  const lastReset = await publicValue('lastReset');
  const kind = await publicValue('lastResetKind');
  expect(Date.parse(lastReset), 'the stack has a last reset (the start values give one)').not.toBeNaN();
  const reset = Date.parse(lastReset);
  const start = reset - 630_000;
  const api: string[] = [];
  const navigations: string[] = [];
  let statusCalls = 0;
  let injected = false;
  try {
    // Task 0 (a): a sessionless GET of the splash with since reaches Splash with since set (the info notice of row 6 renders there).
    const probe = await request.get(`/ocutalon/?since=2026-01-01T00:00:00Z&probe=${Date.now()}`);
    const probeBody = await probe.text();
    console.log(`MEASURED a sessionless GET of /ocutalon/?since=... reaches the splash with since set: ${probeBody.includes('class="notice notice-info"')} (status ${probe.status()})`);
    expect(probeBody, 'the splash shows the notice for a since earlier than the last reset').toContain('class="notice notice-info"');
    expect(probeBody.replace(/ action="[^"]*"/, ''), 'and never writes the value of since (the form keeps the address it was served at, as %CSP.Login does)').not.toContain('2026-01-01');

    await recordAnnouncements(page);
    await recordTraffic(page);
    await page.clock.install({ time: new Date(start) });
    page.on('request', (one: Request) => {
      if (new URL(one.url()).pathname.startsWith('/ocutalon/api/')) api.push(one.url());
    });
    page.on('framenavigated', (frame) => {
      if (frame === page.mainFrame()) navigations.push(frame.url());
    });

    await page.route(`**${STATE}`, async (route) => {
      const response = await route.fetch();
      const body = (await response.json()) as Record<string, unknown> & { status: Array<{ condition: string }>; epoch: string };
      epoch = body.epoch;
      body.status = body.status.filter((one) => one.condition !== 'resetSoon');
      delete body['nextReset'];
      body['nextReset'] = lastReset;
      body['idleSeconds'] = KEEP_ACTIVE_SECONDS;
      await route.fulfill({ response, json: body });
    });
    await page.route(EVENTS_POLL, async (route) => {
      const response = await route.fetch();
      const body = (await response.json()) as { epoch: string; events: LiveEvent[] };
      body.events = body.events.filter((one) => one.type !== 'reset' && !(one.type === 'status' && one.payload['condition'] === 'resetSoon'));
      if (!injected && (await dateNow(page)) >= reset - 300_000) {
        injected = true;
        const after = Number(new URL(route.request().url()).searchParams.get('afterInstance') ?? '0');
        const last = Math.max(after, ...body.events.filter((one) => one.stream === 'instance').map((one) => one.seq));
        body.events.push({ seq: last + 1, stream: 'instance', ts: iso(reset - 299_000), type: 'status', payload: { condition: 'resetSoon', active: true } } as LiveEvent);
      }
      await route.fulfill({ response, json: body });
    });
    const answers: Array<() => Parameters<Route['fulfill']>[0]> = [
      () => ({ status: 200, contentType: 'text/html', body: '<html><body>The demo is resetting.</body></html>' }),
      () => ({ status: 200, json: { ready: false, nextReset: null, busy: false, lastReset: null, lastResetKind: null } }),
      () => ({ status: 200, json: { ready: true, nextReset: null, busy: false, lastReset: iso(start - 3_600_000), lastResetKind: 'scheduled' } }),
      () => ({ status: 200, json: { ready: true, nextReset: null, busy: false, lastReset, lastResetKind: kind || 'scheduled' } }),
    ];
    await page.route(`**${STATUS}*`, async (route) => {
      statusCalls += 1;
      const answer = answers[Math.min(statusCalls, answers.length) - 1]!;
      await route.fulfill(answer());
    });

    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await freeze(page);

    // The last 10 minutes before the reset: the pill, the banner, the last minute.
    const loadedAt = await dateNow(page);
    expect(reset - loadedAt, 'the page loaded before T - 10:00').toBeGreaterThan(600_000);
    await expect(pill(page), 'the pill shows on the online demo').toBeVisible();
    await expect(pillShown(page)).toHaveText(`Next reset ${pageTime(lastReset, 'en-GB', 'Asia/Kolkata')} \u00b7 in 10 min`);
    await expect(pillSpoken(page)).toHaveText(`Next reset ${pageTime(lastReset, 'en-GB', 'Asia/Kolkata')} \u00b7 in 10 minutes`);
    await expect(pill(page), 'it is not urgent above 10 minutes').not.toHaveClass(/reset-countdown-urgent/);
    await expect(pill(page)).toHaveClass(/tabular/);
    expect(await pill(page).evaluate((el) => getComputedStyle(el).fontVariantNumeric)).toContain('tabular-nums');
    expect(await pill(page).locator('[aria-live], [role="timer"], [role="status"]').count(), 'the pill is no live region').toBe(0);
    expect(await bannerIds(page), 'no resetSoon banner yet').not.toContain('resetSoon');

    await runTo(page, reset - 600_000);
    await expect(pill(page), 'urgent from 10 minutes before').toHaveClass(/reset-countdown-urgent/);
    await expect(pillShown(page)).toHaveText(/ \u00b7 in 10 min$/);

    await runTo(page, reset - 301_000);
    expect(await bannerIds(page), 'no banner before 5 minutes').not.toContain('resetSoon');
    await runTo(page, reset - 290_000);
    const banner = page.locator('[data-banner="resetSoon"]');
    await expect(banner, 'the banner appears after 5 minutes').toHaveCount(1);
    await expect(banner.locator('.text')).toHaveText(RESET_BANNER);
    const ids = await bannerIds(page);
    expect(ids.at(-1), 'in the catalog\'s order, Reset soon is the last banner').toBe('resetSoon');
    await expect.poll(() => announcements(page, RESET_BANNER), { message: 'announced once', timeout: 10_000 }).toBe(1);
    await expect(pillShown(page)).toHaveText(/ \u00b7 in 4 min$/);

    // The last minute: the visible text ticks every second, the words stay "in 1 minute".
    await runTo(page, reset - 61_000);
    await expect(pillShown(page)).toHaveText(/ \u00b7 in 1 min$/);
    await runTo(page, reset - 59_000);
    await expect(pillShown(page)).toHaveText(/ \u00b7 in 59 s$/);
    await expect(pillSpoken(page)).toHaveText(/ \u00b7 in 1 minute$/);
    await runTo(page, reset - 58_000);
    await expect(pillShown(page)).toHaveText(/ \u00b7 in 58 s$/);
    await expect(pillSpoken(page), 'the accessible text does not change inside the minute').toHaveText(/ \u00b7 in 1 minute$/);
    await runTo(page, reset - 23_000);
    await expect(pillShown(page)).toHaveText(/ \u00b7 in 23 s$/);
    expect(await announcements(page, RESET_BANNER), 'still announced once').toBe(1);

    // The reset: the resetting view replaces the page, and the live path stops.
    await runTo(page, reset - 1000);
    await expect(page.locator('app-resetting-view')).toHaveCount(0);
    const historyBefore = await page.evaluate(() => history.length);
    await page.getByRole('button', { name: 'Visual Trace', exact: true }).focus();
    await runTo(page, reset);
    const view = page.locator('app-resetting-view');
    await expect(view).toBeVisible();
    await expect(view.getByRole('heading', { level: 1, name: HEADING, exact: true })).toBeVisible();
    await expect(view.getByText(BODY, { exact: true })).toBeVisible();
    await expect(page, 'the tab title').toHaveTitle(TITLE);
    await expect(page.locator('app-header'), 'no header').toHaveCount(0);
    await expect(page.locator('[data-banner]'), 'no banners').toHaveCount(0);
    await expect(page.locator('app-reset-countdown .reset-countdown')).toHaveCount(0);
    const logo = view.locator('img:visible');
    await expect(logo).toHaveCount(1);
    await expect(logo).toHaveAttribute('alt', 'OcuTalon');
    expect((await logo.boundingBox())?.width ?? 0, 'the logo is 320px wide').toBeCloseTo(320, 0);
    expect((await view.locator('.card').boundingBox())?.width ?? 0, 'the card is 400px wide').toBeCloseTo(400, 0);
    await expect(mainOf(page), 'the view is the main region').toBeFocused();
    const apiBefore = api.length;
    const waitFor = async (calls: number): Promise<void> => {
      await expect.poll(() => statusCalls, { message: `status request ${calls}`, timeout: 15_000 }).toBeGreaterThanOrEqual(calls);
      await page.waitForTimeout(200);
    };

    // The CSP session ends, as a reset ends it.
    await signOutGroup(page);
    const baseline = navigations.length;
    await waitFor(1);
    expect(statusCalls, 'one status request at once').toBe(1);
    await page.clock.runFor(10_000);
    await waitFor(2);
    await page.clock.runFor(10_000);
    await waitFor(3);
    await page.waitForTimeout(500);
    expect(navigations.length, 'no navigation on the maintenance page, not ready, or an old last reset').toBe(baseline);
    expect(statusCalls).toBe(3);
    await page.clock.runFor(10_000);
    await waitFor(4);
    await page.waitForURL((url) => url.searchParams.has('since'), { timeout: 15_000 });
    const landed = new URL(page.url());
    expect(landed.pathname).toBe('/ocutalon/');
    const since = landed.searchParams.get('since') ?? '';
    expect(since, 'since is the time the page loaded, UTC to the second').toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    expect(Date.parse(since), 'it is the page\'s load time on its clock').toBeGreaterThanOrEqual(start - 1000);
    expect(Date.parse(since)).toBeLessThanOrEqual(loadedAt);
    expect(navigations.length, 'exactly one navigation').toBe(baseline + 1);
    expect(await page.evaluate(() => history.length), 'the splash replaced the page (location.replace): no new history entry').toBe(historyBefore);

    expect(api.slice(apiBefore), 'no request of the page goes to /ocutalon/api/ after the switch').toEqual([]);

    // The real splash: the reset notice above both cards, with the time in the browser's zone.
    const notice = page.locator('#ocu-notice');
    await expect(notice).toBeVisible();
    const time = pageTime(lastReset, 'en-GB', 'Asia/Kolkata');
    await expect(notice.locator('p')).toHaveText(kind === 'unscheduled' ? RESTART_NOTICE : RESET_NOTICE(time));
    expect(await page.evaluate(() => {
      const found = document.getElementById('ocu-notice');
      const cards = document.querySelector('.splash-cards');
      return !!found && !!cards && (found.compareDocumentPosition(cards) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
    }), 'above both cards').toBe(true);
    const splashNow = await dateNow(page);
    console.log(`MEASURED the installed clock carried across the view's location.replace: the splash's Date.now() is ${iso(splashNow)} (the controlled reset was ${iso(reset)})`);
    expect(Math.abs(splashNow - reset), 'the splash reads the controlled time').toBeLessThan(120_000);
    await page.clock.runFor(30_000);
    await page.waitForTimeout(300);
    expect(navigations.length, 'no second navigation within 30 s of clock').toBe(baseline + 1);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** R2: the real server's clock, a reset four minutes away. */
test('R2: with a reset four minutes away /state, the public status and the anchor agree, the pill is urgent, the banner shows and the splash warns', async ({ page, browser }) => {
  const original = await publicValue('resetAnchor');
  expect(Date.parse(original), 'the stack has an anchor').not.toBeNaN();
  const other = await browser.newContext({ baseURL: process.env['OCUTALON_URL'], timezoneId: 'Asia/Kolkata', locale: 'en-GB' });
  const epochs: string[] = [];
  let changed = false;
  try {
    const anchor = iso((await stackNow()) + 240_000);
    changed = true;
    await setPublic('resetAnchor', anchor);
    expect(await publicValue('resetAnchor'), 'the anchor reads back').toBe(anchor);

    const status = (await (await page.request.get(`${STATUS}?probe=${Date.now()}`)).json()) as { nextReset: string };
    expect(status.nextReset, 'the public status gives the anchor as the next reset').toBe(anchor);

    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    const state = (await (await page.request.get(STATE)).json()) as Record<string, unknown> & { epoch: string; status: Array<{ condition: string; active: boolean }> };
    epochs.push(state.epoch);
    expect(state['nextReset'], '/state gives the same next reset').toBe(anchor);
    expect(Object.keys(state).at(-1), 'as its last key').toBe('nextReset');
    expect(state.status.map((one) => one.condition), '/state\'s status holds resetSoon').toContain('resetSoon');
    expect(state.status.at(-1)?.condition, 'last').toBe('resetSoon');

    await expect(pill(page)).toBeVisible();
    await expect(pill(page), 'the pill is urgent').toHaveClass(/reset-countdown-urgent/);
    await expect(pillShown(page)).toHaveText(new RegExp(`^Next reset ${pageTime(anchor, 'en-GB', 'Asia/Kolkata')} \u00b7 in (3|4) min$`));
    await expect(page.locator('[data-banner="resetSoon"] .text')).toHaveText(RESET_BANNER);
    await expect(page.locator('app-resetting-view'), 'four minutes ahead the page is still the page').toHaveCount(0);

    // A fresh browser: the splash warns under the sign-in card's title, and signing in from it still opens the page.
    const fresh = await other.newPage();
    const served = await fresh.goto(`/ocutalon/?probe=${Date.now()}`);
    expect(await served?.text(), 'the server writes the notice without the hidden attribute (the script would show it either way)').toContain('<div class="notice notice-soon" id="ocu-reset-soon">');
    const soon = fresh.locator('#ocu-reset-soon');
    await expect(soon, 'the warning is shown').toBeVisible();
    await expect(soon).not.toHaveAttribute('hidden', /.*/);
    await expect
      .poll(() => soon.locator('p').evaluate((el) => {
        const copy = el.cloneNode(true) as HTMLElement;
        copy.querySelectorAll('.sr-only').forEach((node) => node.remove());
        return (copy.textContent ?? '').replace(/\s+/g, ' ').trim();
      }), { message: 'the notice reads the UX\'s text with the countdown and time filled', timeout: 10_000 })
      .toMatch(SOON_NOTICE);
    expect(
      await fresh.evaluate(() => {
        const notice = document.getElementById('ocu-reset-soon');
        return notice?.previousElementSibling?.id ?? '';
      }),
      'right after the sign-in card\'s title',
    ).toBe('ocu-signin-h');
    const answered = fresh.waitForResponse((response) => response.request().method() === 'POST');
    await fresh.getByRole('button', { name: 'Sign in and start', exact: true }).click();
    await answered;
    await expect(mainOf(fresh)).toHaveAttribute('data-snapshot', 'loaded');
    const second = (await (await fresh.request.get(STATE)).json()) as { epoch: string };
    epochs.push(second.epoch);
    console.log(`MEASURED R2: the real server's next reset ${anchor} reached /state, the public status, the pill, the banner and the fresh splash's notice`);
  } finally {
    try {
      if (changed) {
        await setPublic('resetAnchor', original);
      }
    } finally {
      await signOutGroup(page);
      await signOutGroup(other);
      await other.close();
      for (const epoch of epochs) await removeSession(epoch);
    }
  }
});

const UNAUTHORIZED = { status: 401, contentType: 'application/json', body: '{}' } as const;

/**
 * Routes the live path of a signed-in page: /state answers nextReset `reset` with no real resetSoon, /events carries no real reset or
 * resetSoon event, and `inject` may add one event to the next /events answer. While `blocked()` is true /state and /events answer 401,
 * and while `dropped()` is true they are refused.
 */
async function routeLivePath(
  page: Page,
  reset: string,
  hooks: { blocked: () => boolean; dropped?: () => boolean; inject: () => Pick<LiveEvent, 'type' | 'payload'> | undefined; epoch: (epoch: string) => void },
): Promise<void> {
  await page.route(`**${STATE}`, async (route) => {
    if (hooks.dropped?.()) return route.abort('connectionrefused');
    if (hooks.blocked()) return route.fulfill(UNAUTHORIZED);
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown> & { status: Array<{ condition: string }>; epoch: string };
    hooks.epoch(body.epoch);
    body.status = body.status.filter((one) => one.condition !== 'resetSoon');
    delete body['nextReset'];
    body['nextReset'] = reset;
    body['idleSeconds'] = KEEP_ACTIVE_SECONDS;
    return route.fulfill({ response, json: body });
  });
  await page.route(EVENTS_POLL, async (route) => {
    if (hooks.dropped?.()) return route.abort('connectionrefused');
    if (hooks.blocked()) return route.fulfill(UNAUTHORIZED);
    const response = await route.fetch();
    const body = (await response.json()) as { epoch: string; events: LiveEvent[] };
    body.events = body.events.filter((one) => one.type !== 'reset' && !(one.type === 'status' && one.payload['condition'] === 'resetSoon'));
    const extra = hooks.inject();
    if (extra) {
      const after = Number(new URL(route.request().url()).searchParams.get('afterInstance') ?? '0');
      const last = Math.max(after, ...body.events.filter((one) => one.stream === 'instance').map((one) => one.seq));
      body.events.push({ seq: last + 1, stream: 'instance', ts: iso(Date.now()), ...extra } as LiveEvent);
    }
    return route.fulfill({ response, json: body });
  });
}

/** R3: a 401 at or after the pending reset belongs to the reset. */
test('R3: a 401 after the pending reset shows the resetting view and does not sign the page out', async ({ page }) => {
  let epoch = '';
  const lastReset = await publicValue('lastReset');
  expect(Date.parse(lastReset), 'the stack has a last reset (the start values give one)').not.toBeNaN();
  const reset = Date.parse(lastReset);
  const navigations: string[] = [];
  let blocked = false;
  try {
    await page.clock.install({ time: new Date(reset - 240_000) });
    page.on('framenavigated', (frame) => {
      if (frame === page.mainFrame()) navigations.push(frame.url());
    });
    await routeLivePath(page, lastReset, { blocked: () => blocked, inject: () => undefined, epoch: (value) => (epoch = value) });
    await page.route(`**${STATUS}*`, (route) => route.fulfill({ status: 200, json: { ready: false, nextReset: null, busy: false, lastReset: null, lastResetKind: null } }));

    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(pill(page)).toBeVisible();
    await expect(page.locator('app-resetting-view'), 'four minutes before the reset the page is still the page').toHaveCount(0);

    // The wall clock moves past the reset; the page's timers do not move, so only an answer of the API can show it.
    const baseline = navigations.length;
    blocked = true;
    await page.clock.setSystemTime(new Date(reset + 2000));
    const view = page.locator('app-resetting-view');
    await expect(view, 'the 401 past the reset shows the resetting view').toBeVisible({ timeout: 60_000 });
    await expect(view.getByRole('heading', { level: 1, name: HEADING, exact: true })).toBeVisible();
    await page.waitForTimeout(500);
    expect(navigations.length, 'the page did not go to the sign-in page').toBe(baseline);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** R3b: lost contact past the pending reset belongs to the reset. */
test('R3b: lost contact after the pending reset shows the resetting view', async ({ page }) => {
  let epoch = '';
  const lastReset = await publicValue('lastReset');
  expect(Date.parse(lastReset), 'the stack has a last reset (the start values give one)').not.toBeNaN();
  const reset = Date.parse(lastReset);
  let dropped = false;
  try {
    await page.clock.install({ time: new Date(reset - 240_000) });
    await routeLivePath(page, lastReset, { blocked: () => false, dropped: () => dropped, inject: () => undefined, epoch: (value) => (epoch = value) });
    await page.route(`**${STATUS}*`, (route) => route.fulfill({ status: 200, json: { ready: false, nextReset: null, busy: false, lastReset: null, lastResetKind: null } }));

    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(page.locator('app-resetting-view'), 'four minutes before the reset the page is still the page').toHaveCount(0);

    // The wall clock moves past the reset and the API stops answering: the page's contact goes from ok to reconnecting.
    dropped = true;
    await page.clock.setSystemTime(new Date(reset + 2000));
    await expect(page.locator('app-resetting-view'), 'lost contact past the reset shows the resetting view').toBeVisible({ timeout: 90_000 });
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** R3c: an answer of the live path past the pending reset belongs to the reset. */
test('R3c: an answer of the live path after the pending reset shows the resetting view before the reset timer would', async ({ page }) => {
  let epoch = '';
  const lastReset = await publicValue('lastReset');
  expect(Date.parse(lastReset), 'the stack has a last reset (the start values give one)').not.toBeNaN();
  const reset = Date.parse(lastReset);
  try {
    await page.clock.install({ time: new Date(reset - 240_000) });
    await routeLivePath(page, lastReset, { blocked: () => false, inject: () => undefined, epoch: (value) => (epoch = value) });
    await page.route(`**${STATUS}*`, (route) => route.fulfill({ status: 200, json: { ready: false, nextReset: null, busy: false, lastReset: null, lastResetKind: null } }));

    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(page.locator('app-resetting-view'), 'four minutes before the reset the page is still the page').toHaveCount(0);

    // The wall clock moves past the reset while the live path keeps answering and the page's contact stays ok; the reset timer is still
    // about four minutes away, so only the check at an answer can show the reset within the wait below.
    await page.clock.setSystemTime(new Date(reset + 2000));
    await expect(page.locator('app-resetting-view'), 'the next answer past the reset shows the resetting view').toBeVisible({ timeout: 30_000 });
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/**
 * R4: a reset event moves the pending reset while more than five minutes remain. The page's next reset is the case's own, two hours
 * ahead on the routed /state, so the case does not depend on the stack's schedule.
 */
test('R4: a reset event with a later time moves the pill', async ({ page }) => {
  let epoch = '';
  let send = false;
  let sent = false;
  try {
    const next = iso(Math.floor(Date.now() / 60_000) * 60_000 + 2 * 3_600_000);
    const later = iso(Date.parse(next) + 4 * 3_600_000);
    await routeLivePath(page, next, {
      blocked: () => false,
      inject: () => {
        if (!send || sent) return undefined;
        sent = true;
        return { type: 'reset', payload: { nextReset: later } } as Pick<LiveEvent, 'type' | 'payload'>;
      },
      epoch: (value) => (epoch = value),
    });
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(pillShown(page)).toHaveText(new RegExp(`^Next reset ${pageTime(next, 'en-GB', 'Asia/Kolkata')} \u00b7 in 1 h \\d+ min$`));
    send = true;
    await expect(pillShown(page), 'the event moves the pill to the later reset').toHaveText(
      new RegExp(`^Next reset ${pageTime(later, 'en-GB', 'Asia/Kolkata')} \u00b7 in [56] h \\d+ min$`),
      { timeout: 60_000 },
    );
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** R5: the splash's script shows the reset-soon notice as the reset comes within five minutes. */
test('R5: the splash reveals the reset-soon notice at five minutes, announces it once and hides it after the reset', async ({ page }) => {
  try {
    await recordSplashAnnouncements(page);
    const status = (await (await page.request.get(`${STATUS}?probe=${Date.now()}`)).json()) as { nextReset: string };
    const due = Date.parse(status.nextReset);
    expect(due, 'the stack has a next reset').not.toBeNaN();
    const start = due - 360_000;
    await page.clock.install({ time: start - 60_000 });
    await page.goto(`/ocutalon/?probe=${Date.now()}r5`);
    await page.clock.pauseAt(start);
    await page.clock.runFor(1000);

    const soon = page.locator('#ocu-reset-soon');
    const soonAnnouncements = async (): Promise<string[]> => (await splashAnnouncements(page)).filter((one) => one.startsWith('The demo resets in'));
    await expect(soon, 'six minutes ahead the notice is in the page and hidden').toBeHidden();
    await expect(soon).toHaveAttribute('hidden', /.*/);
    expect(await soonAnnouncements()).toEqual([]);

    await page.clock.runFor(62_000);
    await expect(soon, 'inside five minutes the script shows it').toBeVisible();
    await expect.poll(soonAnnouncements, { message: 'and announces it once', timeout: 10_000 }).toHaveLength(1);
    expect((await soonAnnouncements())[0]).toMatch(/^The demo resets in [45] minutes?, which may cut your run short\. You can start now or come back after \d{1,2}:\d{2}\.$/);
    await page.clock.runFor(30_000);
    await expect(soon).toBeVisible();
    expect(await soonAnnouncements(), 'still announced once').toHaveLength(1);

    await page.clock.runFor(290_000);
    await expect(soon, 'after the reset the notice is hidden again (the next reset is hours away)').toBeHidden();
  } finally {
    await signOutGroup(page);
  }
});

/** Routes a signed-in page for R6 and R7: the live path of R3 with the pending reset `lastReset`, and a status that is not ready. */
async function routeBeforeReset(page: Page, lastReset: string, hooks: { blocked: () => boolean; epoch: (epoch: string) => void }): Promise<void> {
  await routeLivePath(page, lastReset, { blocked: hooks.blocked, inject: () => undefined, epoch: hooks.epoch });
  await page.route(`**${STATUS}*`, (route) => route.fulfill({ status: 200, json: { ready: false, nextReset: null, busy: false, lastReset: null, lastResetKind: null } }));
}

test('R6: a 401 before the pending reset signs the page out and does not show the resetting view', async ({ page }) => {
  let epoch = '';
  const lastReset = await publicValue('lastReset');
  expect(Date.parse(lastReset), 'the stack has a last reset (the start values give one)').not.toBeNaN();
  const reset = Date.parse(lastReset);
  const navigations: string[] = [];
  let blocked = false;
  try {
    await page.clock.install({ time: new Date(reset - 240_000) });
    page.on('framenavigated', (frame) => {
      if (frame === page.mainFrame()) navigations.push(frame.url());
    });
    await routeBeforeReset(page, lastReset, { blocked: () => blocked, epoch: (value) => (epoch = value) });

    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(pill(page), 'the page has its pending reset, four minutes ahead').toBeVisible();
    await expect(page.locator('app-resetting-view')).toHaveCount(0);

    // The page's clock stays four minutes before the reset; the API stops accepting the session, and the CSP session ends, as it does
    // when a session ends elsewhere (while it lasts, the sign-in address would serve the page again).
    blocked = true;
    await signOutGroup(page);
    await page.waitForURL(/[?&]since=/, { timeout: 60_000, waitUntil: 'commit' });
    expect(navigations.some((url) => url.includes('signedOut=1')), 'the online demo never takes the local sign-in page, and its "You were signed out." text, for a 401 (Story 16.4)').toBe(false);
    await expect(page.locator('app-resetting-view'), 'and the resetting view never showed').toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Sign in and start', exact: true }), 'the sign-in page shows').toBeVisible();
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

test('R7: the resetting view shows the logo of the page\'s theme and follows a change of scheme', async ({ page }) => {
  let epoch = '';
  const lastReset = await publicValue('lastReset');
  expect(Date.parse(lastReset), 'the stack has a last reset (the start values give one)').not.toBeNaN();
  const reset = Date.parse(lastReset);
  let blocked = false;
  try {
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.clock.install({ time: new Date(reset - 240_000) });
    await routeBeforeReset(page, lastReset, { blocked: () => blocked, epoch: (value) => (epoch = value) });

    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    blocked = true;
    await page.clock.setSystemTime(new Date(reset + 2000));
    const view = page.locator('app-resetting-view');
    await expect(view, 'the 401 past the reset shows the resetting view').toBeVisible({ timeout: 60_000 });

    const light = view.locator('img[src*="OcuTalon-Logo-light-"]');
    const dark = view.locator('img[src*="OcuTalon-Logo-dark-"]');
    await expect(dark, 'a dark scheme shows the dark logo').toBeVisible();
    await expect(light, 'and not the light one').toBeHidden();
    expect((await dark.boundingBox())?.width ?? 0, 'at 320px').toBeCloseTo(320, 0);

    await page.emulateMedia({ colorScheme: 'light' });
    await expect(light, 'a light scheme shows the light logo').toBeVisible();
    await expect(dark, 'and not the dark one').toBeHidden();
    expect((await light.boundingBox())?.width ?? 0, 'at 320px').toBeCloseTo(320, 0);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

test('R8: the pill sits after the Status button and before the Visual Trace button in the header', async ({ page }) => {
  let epoch = '';
  /** The header's right group by what each child is: the Status button, the pill, the Visual Trace button, or something else. */
  const rightGroup = (): Promise<string[]> =>
    page.evaluate(() =>
      [...(document.querySelector('app-header .side.right')?.children ?? [])].map((el) =>
        el.matches('.status-button') ? 'status' : el.matches('app-reset-countdown') ? 'pill' : (el.textContent ?? '').includes('Visual Trace') ? 'trace' : 'other',
      ),
    );
  try {
    await page.setViewportSize({ width: 1100, height: 800 });
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    epoch = ((await (await page.request.get(STATE)).json()) as { epoch: string }).epoch;
    await expect(pill(page), 'the online demo has its pill (the unit\'s reset is two hours ahead)').toBeVisible();
    await expect(page.locator('app-header .status-button'), 'the drawer band has the Status button').toBeVisible();
    expect((await rightGroup()).filter((one) => one !== 'other'), 'drawer band: Status, then the pill, then Visual Trace').toEqual(['status', 'pill', 'trace']);

    await page.setViewportSize({ width: 1280, height: 800 });
    await expect(page.locator('app-header .status-button'), 'the wide layout has no Status button').toHaveCount(0);
    await expect(pill(page)).toBeVisible();
    expect((await rightGroup()).filter((one) => one !== 'other'), 'wide: the pill, then Visual Trace').toEqual(['pill', 'trace']);

    // With the pill, the header still fits the narrowest drawer band and the stacked column's 640px.
    for (const width of [1024, 640]) {
      await page.setViewportSize({ width, height: 800 });
      await expect(pill(page)).toBeVisible();
      const fit = await page.evaluate(() => {
        const root = document.scrollingElement ?? document.documentElement;
        const header = document.querySelector('app-header .header')?.getBoundingClientRect();
        const ends = [...(document.querySelector('app-header .side.right')?.children ?? [])].map((el) => el.getBoundingClientRect().right);
        return { across: root.scrollWidth - root.clientWidth, past: Math.max(...ends) - (header?.right ?? 0) };
      });
      console.log(`MEASURED R8 at ${width}px with the pill: the page scrolls across by ${fit.across}px; the header's right group ends ${fit.past}px past the header's edge`);
      expect(fit.across, `at ${width}px the page does not scroll across`).toBeLessThanOrEqual(0);
      expect(fit.past, `at ${width}px the header's right group ends inside the header`).toBeLessThanOrEqual(0);
    }
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** R9: the resetting view's status polls carry no credentials; the signed-in page's own requests carry the session. */
test('R9: the resetting view asks the public status with no cookie', async ({ page }) => {
  let epoch = '';
  const documents: Request[] = [];
  const polls: Request[] = [];
  try {
    page.on('request', (one: Request) => {
      const url = new URL(one.url());
      if (url.pathname === STATUS && url.searchParams.has('t')) polls.push(one);
      else if (one.resourceType() === 'document' && url.pathname === '/ocutalon/') documents.push(one);
    });
    // The page's pending reset is a few seconds ahead on the routed /state (or already past, on a slow sign-in); the public status is not
    // routed, so the view's polls reach the server (ready, with the stack's old last reset, so the view stays).
    const reset = iso(Date.now() + 12_000);
    await routeLivePath(page, reset, { blocked: () => false, inject: () => undefined, epoch: (value) => (epoch = value) });

    await signInFromSplash(page);
    await expect(page.locator('app-resetting-view'), 'the page enters the resetting view at its pending reset').toBeVisible({ timeout: 90_000 });
    const control = documents.at(-1);
    expect(control, 'the signed-in page was a document request to /ocutalon/').toBeTruthy();
    await expect.poll(() => polls.length, { message: 'the view asks the public status', timeout: 15_000 }).toBeGreaterThanOrEqual(1);
    await polls[0]!.response();
    const sent = await polls[0]!.allHeaders();
    const own = await control!.allHeaders();
    console.log(`MEASURED Story 16.8 Task 0 (c): the view's status poll carries a Cookie header: ${sent['cookie'] !== undefined}; the signed-in page's request carries one: ${own['cookie'] !== undefined}`);
    expect(own['cookie'] ?? '', 'the control: the signed-in page\'s own request carries the session cookie').not.toBe('');
    expect(sent['cookie'], 'the status poll carries no cookie').toBeUndefined();
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});
