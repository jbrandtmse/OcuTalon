import { expect, test, type Page } from '@playwright/test';

import { notBuilt } from '../../e2e/demo-path/not-built';
import { EVENTS, STATE } from '../../e2e/support/api';
import { recordTraffic, traffic } from '../../e2e/support/clock';
import {
  advance,
  confirmSignOut,
  cspSessionExists,
  epochOf,
  expectTraceSignIn,
  fixtureTurn,
  landedOn,
  landedOnSplash,
  openSession,
  openTraceTab,
  pressSignOut,
  recordRequests,
  removeSession,
  sessionRow,
  signInFromSplash,
  signOutGroup,
  watchText,
} from '../support';

/**
 * Story 16.4, leaving the page frees its place (matrix rows 3, 5, 7, 9 and 9b), on the throwaway of docker/tests/test-online-session.sh: the
 * stack's CSP sessions time out after 120 s and the page's idle cap is the seeded 600 s. Every case is the DEMOACCOUNT, finds its visitor's
 * Session row by the epoch of its own /state, signs out of the whole sign-in group and removes its rows in `finally`.
 * - L1 (row 3, AC 1): a reload keeps the session: the same epoch each time, the main page and not the splash, no request to IRISLogout or to
 *   /session/end, and the row's CSP session still exists.
 * - L2 (row 5, AC 3): the idle cap, on the page's own clock (installed before the load, moved on in steps of five seconds so that the page
 *   polls as it does): polls do not count, a key press and a click do, and 600 s with none lands on the splash with its load time and the
 *   place-freed notice above both cards; the CSP session is gone, a trace page needs a sign-in, and signing in resumes the epoch.
 * - L3 (row 7, AC 3): a 401 (the CSP session ended out of band) takes the page to the same splash and notice, never to the sign-in page or
 *   "You were signed out.", and no request of any kind (an API call or a sign-out) follows it.
 * - L4 (row 9, AC 4): an epoch change that the answers inject is never applied: the page shows nothing of the other session, asks for no
 *   snapshot, signs the group out and lands on the splash with ended=1 and no notice.
 * - L4b (row 9, AC 4): the same through the snapshot: a poll that skips a Seq in the page's own epoch makes the page ask for the snapshot, and
 *   a snapshot of another epoch is never applied either.
 * - L4c (the group sign-out's bound): a sign-out request that is never answered holds the page for 3 s at most.
 * - L5 (row 9b, AC 4): a real epoch change: another page of the context signs out and in again, and the first page, on the new session's
 *   cookie, never shows the new session's turn, signs out and lands on the splash with ended=1.
 * - L6: Telegram keeps working with no CSP session open (Story 31.3).
 * The texts are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 300_000 });

const PLACE_FREED = 'You were away for a while, so your place was freed for other visitors. Sign in again to pick up where you left off.';
const SIGNED_OUT = 'You were signed out.';
const EVENTS_POLL = /\/ocutalon\/api\/v1\/events\?/;
const CAP_MS = 600_000;
/** How long after the group sign-out request the page may land on the splash: SIGN_OUT_LIMIT_MS (3 s) and the splash's own load. */
const SIGN_OUT_BOUND_MS = 5000;

const mainOf = (page: Page) => page.locator('main.main');

/** The splash after a return: the notice reads the place-freed text above both cards, and the address has the page's load time. */
async function expectPlaceFreed(page: Page, loadedAt: number): Promise<void> {
  const url = new URL(page.url());
  expect(url.pathname, 'the splash').toBe('/ocutalon/');
  expect(url.searchParams.has('signedOut'), 'never the local sign-in page').toBe(false);
  const since = Date.parse(url.searchParams.get('since') ?? '');
  expect(Number.isNaN(since) ? Number.NaN : Math.abs(since - loadedAt), 'since is the time the page loaded, to the second').toBeLessThan(5000);
  await expect(page.locator('#ocu-notice'), 'the notice reads the place-freed text').toHaveText(PLACE_FREED);
  const above = await page.evaluate(() => {
    const notice = document.querySelector('#ocu-notice');
    const cards = document.querySelector('.splash-cards');
    return !!notice && !!cards && !!(notice.compareDocumentPosition(cards) & Node.DOCUMENT_POSITION_FOLLOWING);
  });
  expect(above, 'above both cards').toBe(true);
  expect(await page.content(), 'and no "You were signed out." text anywhere').not.toContain(SIGNED_OUT);
}

/** L1: a reload keeps the session and signs nothing out. */
test('L1: a reload keeps the same session and sends no sign-out', async ({ page, context }) => {
  let epoch = '';
  try {
    const log = recordRequests(context);
    epoch = await openSession(page);
    const row = await sessionRow(epoch);
    expect(row?.cspSessionId, 'the row names its CSP session').toBeTruthy();
    const mark = log.mark();
    for (let reload = 1; reload <= 2; reload += 1) {
      await page.reload();
      await expect(mainOf(page), `reload ${reload}: the main page loads its snapshot`).toHaveAttribute('data-snapshot', 'loaded');
      expect(new URL(page.url()).pathname, `reload ${reload}: still the application, not the splash`).toBe('/ocutalon/');
      await expect(page.getByRole('button', { name: 'Sign in and start', exact: true }), `reload ${reload}: no sign-in form`).toHaveCount(0);
      expect(await epochOf(page), `reload ${reload}: the same epoch`).toBe(epoch);
    }
    const sent = log.since(mark).filter((url) => url.includes('IRISLogout') || url.includes('/session/end'));
    expect(sent, 'no request to IRISLogout or /session/end').toEqual([]);
    expect(await cspSessionExists(row!.cspSessionId), "and the row's CSP session still exists").toBe(true);
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** L2: the idle cap. */
test('L2: 600 s without a key press, click or sent message frees the place; polls do not count, a key press and a click do', async ({ page, context }) => {
  let epoch = '';
  try {
    await recordTraffic(page);
    await page.clock.install();
    epoch = await openSession(page);
    const loadedAt = await page.evaluate(() => Date.now());
    await openTraceTab(context);

    const known = (await traffic(page)).length;
    await advance(page, CAP_MS - 10_000);
    const polls = (await traffic(page)).slice(known).filter((one) => one.path === EVENTS && one.status === 200);
    expect(polls.length, 'the page polled and was answered in 590 s').toBeGreaterThan(0);
    await expect(mainOf(page), '590 s with no activity: still on the page').toHaveAttribute('data-snapshot', 'loaded');

    await page.keyboard.press('Shift');
    await advance(page, CAP_MS - 10_000);
    await expect(mainOf(page), 'a key press at 590 s, then 590 s more: still there').toHaveAttribute('data-snapshot', 'loaded');

    await page.locator('body').click({ position: { x: 3, y: 3 } });
    await advance(page, CAP_MS - 10_000);
    await expect(mainOf(page), 'a click on the page, then 590 s more: still there').toHaveAttribute('data-snapshot', 'loaded');

    try {
      await page.clock.runFor(20_000);
    } catch {
      /* The page leaves while the clock runs, which ends its execution context. */
    }
    await landedOn(page, /\/ocutalon\/\?since=/, 60_000);
    await expectPlaceFreed(page, loadedAt);
    expect((await context.request.get(STATE)).status(), "the context's /state is 401").toBe(401);
    await expectTraceSignIn(context, "a new tab's trace address shows the trace sign-in form");

    await page.clock.resume();
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    expect(await epochOf(page), 'signing in from the splash gives the same epoch').toBe(epoch);
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** L3: a 401 takes the online demo's page to the splash and its notice. */
test('L3: a 401 returns the page to the splash with the place-freed notice, never to "You were signed out."', async ({ page, context }) => {
  let epoch = '';
  try {
    const log = recordRequests(context);
    const api: string[] = [];
    let at401 = -1;
    page.on('request', (request) => {
      if (new URL(request.url()).pathname.startsWith('/ocutalon/api/')) api.push(request.url());
    });
    page.on('response', (response) => {
      if (at401 < 0 && response.status() === 401 && new URL(response.url()).pathname.startsWith('/ocutalon/api/')) at401 = api.length;
    });
    epoch = await openSession(page);
    const loadedAt = await page.evaluate(() => Date.now());
    const probe = `${Date.now()}l3`;
    const mark = log.mark();
    await context.request.get(`/ocutalon/?IRISLogout=end&probe=${probe}`);
    await landedOn(page, /\/ocutalon\/\?since=/, 60_000);
    await expectPlaceFreed(page, loadedAt);
    expect(at401, 'the poll was answered 401').toBeGreaterThanOrEqual(0);
    expect(api.length, 'no API request follows the 401').toBe(at401);
    expect(log.since(mark).filter((url) => url.includes('IRISLogout') || url.includes('/session/end')), 'and the page sent no sign-out after it').toEqual([]);
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    expect(await epochOf(page), 'signing in gives the same epoch').toBe(epoch);
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** L4: an injected epoch change is never applied. */
test('L4: a poll of another epoch is never applied: the page signs the group out and lands on the splash with ended=1', async ({ page, context }) => {
  let epoch = '';
  const other = 'zz-other-epoch';
  const secret = `zz other session ${Date.now()}`;
  try {
    const log = recordRequests(context);
    const seen = await watchText(page, secret);
    let armed = false;
    let injected = false;
    let stateAfter = 0;
    const entry = (): Record<string, unknown> => ({
      type: 'chat.message',
      payload: { ref: 'zzother', clientId: 'zzother', text: secret, state: 'done', channel: 'web', createdAt: new Date().toISOString(), fromGuide: false },
    });
    await page.route(EVENTS_POLL, async (route) => {
      if (!armed || injected) return route.continue();
      injected = true;
      return route.fulfill({ status: 200, json: { epoch: other, events: [{ seq: 1, stream: 'session', ts: new Date().toISOString(), ...entry() }] } });
    });
    await page.route(`**${STATE}`, async (route) => {
      if (!armed) return route.continue();
      stateAfter += 1;
      const response = await route.fetch();
      const body = (await response.json()) as Record<string, unknown>;
      body['epoch'] = other;
      body['chat'] = [entry()];
      return route.fulfill({ response, json: body });
    });
    epoch = await openSession(page);
    const loadedAt = await page.evaluate(() => Date.now());
    const mark = log.mark();
    armed = true;
    await landedOn(page, /[?&]ended=1/, 60_000);
    const url = new URL(page.url());
    expect(url.pathname, 'the splash').toBe('/ocutalon/');
    expect(Math.abs(Date.parse(url.searchParams.get('since') ?? '') - loadedAt), 'with the time the page loaded').toBeLessThan(5000);
    expect(log.since(mark).some((one) => one.includes('IRISLogout=end')), 'the page sent the group sign-out').toBe(true);
    expect(stateAfter, 'and never asked for the snapshot again').toBe(0);
    expect(seen.seen(), 'it never showed the other session').toBe(false);
    await expect(page.locator('#ocu-notice'), 'the splash has no notice').toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Sign in and start', exact: true })).toBeVisible();
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** Routes the next /events answer to a skipped Seq of the page's own epoch, so that the page asks for the snapshot, and answers the snapshot with another epoch. */
async function routeSnapshotOfAnotherEpoch(page: Page, epoch: string, secret: string): Promise<{ arm: () => void; snapshots: () => number }> {
  const other = 'zz-other-epoch';
  const entry = (): Record<string, unknown> => ({
    type: 'chat.message',
    payload: { ref: 'zzother', clientId: 'zzother', text: secret, state: 'done', channel: 'web', createdAt: new Date().toISOString(), fromGuide: false },
  });
  let armed = false;
  let skipped = false;
  let snapshots = 0;
  await page.route(EVENTS_POLL, async (route) => {
    if (!armed || skipped) return route.continue();
    skipped = true;
    return route.fulfill({ status: 200, json: { epoch, events: [{ seq: 999_999, stream: 'session', ts: new Date().toISOString(), ...entry() }] } });
  });
  await page.route(`**${STATE}`, async (route) => {
    if (!armed) return route.continue();
    snapshots += 1;
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    body['epoch'] = other;
    body['chat'] = [entry()];
    return route.fulfill({ response, json: body });
  });
  return { arm: () => void (armed = true), snapshots: () => snapshots };
}

/** L4b: a snapshot of another epoch, reached through a skipped Seq, is never applied. */
test('L4b: a snapshot of another epoch is never applied either: the page signs the group out and lands on the splash with ended=1', async ({ page, context }) => {
  let epoch = '';
  const secret = `zz other snapshot ${Date.now()}`;
  try {
    const log = recordRequests(context);
    const seen = await watchText(page, secret);
    epoch = await openSession(page);
    const loadedAt = await page.evaluate(() => Date.now());
    const routes = await routeSnapshotOfAnotherEpoch(page, epoch, secret);
    const mark = log.mark();
    routes.arm();
    await landedOn(page, /[?&]ended=1/, 60_000);
    const url = new URL(page.url());
    expect(url.pathname, 'the splash').toBe('/ocutalon/');
    expect(Math.abs(Date.parse(url.searchParams.get('since') ?? '') - loadedAt), 'with the time the page loaded').toBeLessThan(5000);
    expect(routes.snapshots(), 'the page asked for the snapshot once, because of the skipped Seq').toBe(1);
    expect(log.since(mark).some((one) => one.includes('IRISLogout=end')), 'the page sent the group sign-out').toBe(true);
    expect(seen.seen(), 'it never showed the other session').toBe(false);
    await expect(page.locator('#ocu-notice'), 'the splash has no notice').toHaveCount(0);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** L4c: the group sign-out holds the page for 3 s at most. */
test('L4c: a group sign-out request that is never answered holds the page for 3 s at most', async ({ page, context }) => {
  let epoch = '';
  const secret = `zz other bound ${Date.now()}`;
  try {
    const log = recordRequests(context);
    epoch = await openSession(page);
    const routes = await routeSnapshotOfAnotherEpoch(page, epoch, secret);
    let sentAt = 0;
    await page.route(/IRISLogout=end/, () => {
      if (sentAt === 0) sentAt = Date.now();
    });
    const mark = log.mark();
    routes.arm();
    // The case times the landing, so it waits for the commit and navigates nowhere afterwards (landedOn waits for the load).
    await page.waitForURL(/[?&]ended=1/, { timeout: 30_000, waitUntil: 'commit' });
    const landedAt = Date.now();
    expect(log.since(mark).some((one) => one.includes('IRISLogout=end')), 'the page sent the group sign-out, which nothing answered').toBe(true);
    expect(sentAt, 'the held sign-out request was seen').toBeGreaterThan(0);
    expect(landedAt - sentAt, 'and the page landed on the splash within 3 s of it, plus the splash load').toBeLessThan(SIGN_OUT_BOUND_MS);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** L5: a real epoch change, from another page of the same browser. */
test('L5: when another page ends the session and starts a new one, the first page shows nothing of it and signs out with ended=1', async ({ page, context }) => {
  const epochs: string[] = [];
  const secret = `zz second session ${Date.now()}`;
  try {
    const log = recordRequests(context);
    const seen = await watchText(page, secret);
    const first = await openSession(page);
    epochs.push(first);
    const loadedAt = await page.evaluate(() => Date.now());
    const second = await context.newPage();
    await second.goto(`/ocutalon/?probe=${Date.now()}l5`);
    await expect(mainOf(second)).toHaveAttribute('data-snapshot', 'loaded');

    await page.route(EVENTS_POLL, (route) => route.abort('connectionrefused'));
    await pressSignOut(second);
    await confirmSignOut(second);
    await landedOnSplash(second, 60_000);
    await signInFromSplash(second);
    await expect(mainOf(second)).toHaveAttribute('data-snapshot', 'loaded');
    const next = await epochOf(second);
    epochs.push(next);
    expect(next, 'the second page started a new session').not.toBe(first);
    const row = await sessionRow(next);
    expect(row, "the new session's row").toBeDefined();
    await fixtureTurn(row!.ref, secret);

    const mark = log.mark();
    await page.unroute(EVENTS_POLL);
    await landedOn(page, /[?&]ended=1/, 90_000);
    const url = new URL(page.url());
    expect(url.pathname, 'the first page is on the splash').toBe('/ocutalon/');
    expect(Math.abs(Date.parse(url.searchParams.get('since') ?? '') - loadedAt), 'with the time it loaded').toBeLessThan(5000);
    expect(log.since(mark).some((one) => one.includes('IRISLogout=end')), 'it sent the group sign-out').toBe(true);
    expect(seen.seen(), "it never showed the new session's turn").toBe(false);
    await expect(page.locator('#ocu-notice'), 'and the splash has no notice').toHaveCount(0);
    await second.close();
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    expect(await epochOf(page), "a sign-in from the first page gives an epoch other than its first one").not.toBe(first);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    for (const epoch of epochs) await removeSession(epoch);
  }
});

notBuilt('L6: a paired Telegram chat keeps working while no CSP session is open', '31.3');
