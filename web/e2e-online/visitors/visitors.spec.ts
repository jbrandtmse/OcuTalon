import { expect, test, type APIRequestContext, type BrowserContext, type Page } from '@playwright/test';

import { STATE } from '../../e2e/support/api';
import { chk, irisScript } from '../../e2e/support/iris';
import { postTurn, type Cursor } from '../../e2e/support/trace';
import {
  BUSY_HEADER,
  confirmSignOut,
  counterRows,
  DEMO_BUSY_TEXT,
  expectOpenedDirectly,
  landedOnSplash,
  leaveVisitor,
  openVisitor,
  opensTabStrict,
  pressSignOut,
  probed,
  publicValue,
  readStatus,
  removeCounterRows,
  removeSession,
  resumeCookie,
  sessionRowCount,
  setPublic,
  signInOverHttpFrom,
  signOutGroup,
  SIGN_OUT,
  statusAnswer,
  type StatusReading,
  type Visitor,
} from '../support';

/**
 * Story 29.7, the visitor count of the demo's busy state (V1; matrix rows 1 to 6 and 9, AC1 to AC3, AC5 and AC7). The project runs on the
 * online-visitors throwaway, whose proxy address is the address IRIS sees for the host's requests, so that every browser and API request
 * is proxied and counted under its X-Forwarded-For (addresses 198.51.100.71 to .80, one per visitor). One test, in this order:
 * - row 1: five browser visitors V1 to V5 are signed in and polling; the plain status and its trace form (`?for=trace`) are both not
 *   busy, with no marker header. V6 signs in from the splash and gets the shell; then the plain status is busy with the marker header
 *   and the status 200, the trace form is not busy with no header, and a fresh context's splash shows the busy error with the header;
 * - row 2: a seventh visitor opens the splash, which shows the busy error, and presses Sign in and start: the answer is 200 with the busy
 *   error and the header, no shell, no resume cookie, /state answers 401, and no Session row and no counter row is made;
 * - row 3: the proxy address is set to one that no request comes from, a sign-in over HTTP is made (the probe's path), and the address
 *   is put back and read back: the direct sign-in gets the shell and /state 200 and is not counted;
 * - row 4: V6 signs out with the page's Sign out; the plain status is not busy at the first read after V6 lands on the splash, while the
 *   direct sign-in is still signed in; then that sign-in signs out;
 * - row 5: T, an API visitor that makes no request after its one /state, makes the sixth counted visitor again (plain busy, trace form
 *   not busy), and V1 presses Open my conversation in Visual Trace: the page asks `?for=trace&t=<13 digits>`, the trace window opens at
 *   the link's page and session, and no Demo busy banner shows;
 * - row 6: 110 s after T's last request the plain status is still busy; by 140 s it is not, while V1's trace session (kept alive by a
 *   request every 30 s) is still in the session store, since another application's session never counts; a proxied sign-in from a new
 *   address then gets in. The seconds T took to leave are printed as MEASURED V1;
 * - row 9: with the full house, the plain status answers the query forms; only exactly one `for=trace` reports not busy, every answer is
 *   200 with exactly the five keys and no Set-Cookie.
 * `finally` signs every context out of the whole sign-in group, removes every session row and counter row it made, and puts the proxy
 * address back. The file runs in full Chromium with its popup blocker on (as busy.spec.ts does), so a window that the page opens after the
 * click's activation has run out is blocked, as in a visitor's browser. The texts are written out here, as the independent oracle of the
 * page's own.
 */
test.describe.configure({ timeout: 360_000 });
test.use({ channel: 'chromium', launchOptions: { ignoreDefaultArgs: ['--disable-popup-blocking'] } });

/** The client address of each party of the case; the proxy's X-Forwarded-For carries it. */
const ADDRESS = {
  v: ['198.51.100.71', '198.51.100.72', '198.51.100.73', '198.51.100.74', '198.51.100.75', '198.51.100.76'],
  seventh: '198.51.100.77',
  t: '198.51.100.78',
  direct: '198.51.100.79',
  late: '198.51.100.80',
} as const;

/** An address that no request of the run comes from (TEST-NET-1): with the proxy address set to it, no sign-in is proxied. */
const UNUSED_PROXY = '192.0.2.10';

const BANNER = '[data-banner="demoBusy"]';
const KEYS = ['ready', 'nextReset', 'busy', 'lastReset', 'lastResetKind'];
const NOT_BUSY: StatusReading = { busy: false, header: undefined, code: 200 };
const BUSY: StatusReading = { busy: true, header: '1', code: 200 };

const sleep = (ms: number): Promise<void> => new Promise((done) => setTimeout(done, ms));

/** The sessions of the CSP session store that belong to a trace application and have not timed out (the stored list's positions 13 and 3). */
async function liveTraceSessions(): Promise<number> {
  const lines = await irisScript(
    [
      'Set s=$ZTimeStamp Set now=($Piece(s,",")*86400+$Piece(s,",",2))\\1 Set n=0 Set id=0',
      'For { Set id=$Order(^%cspSession(id)) Quit:id=""  Set d=$Get(^%cspSession(id)) If ($ListGet(d,13)["/ocutalon/trace/")&&($ListGet(d,3)>now) Set n=n+1 }',
      'Write !,"CHK|trace|",n',
    ].join('\n'),
  );
  return Number(chk(lines, 'trace') ?? '-1');
}

/** Both forms of the status as the case reads them: the plain form and `?for=trace`. */
async function readBoth(api: APIRequestContext): Promise<{ plain: StatusReading; trace: StatusReading }> {
  return { plain: await readStatus(api), trace: await readStatus(api, 'trace') };
}

/** The splash of a context that holds no session shows the busy error. */
async function expectBusySplash(page: Page, label: string): Promise<void> {
  const answered = await page.goto(probed('/ocutalon/'));
  expect(answered?.status(), `${label}: the splash is served`).toBe(200);
  expect(answered?.headers()[BUSY_HEADER], `${label}: with the marker header`).toBe('1');
  await expect(page.locator('#ocu-error'), `${label}: the splash shows the busy error`).toContainText(DEMO_BUSY_TEXT);
}

test('V1: the 6th visitor gets in and the 7th sees Demo busy, a place leaves at sign-out and at the timeout, and Visual Trace opens at a full house', async ({
  browser,
  playwright,
}) => {
  const savedProxy = await publicValue('proxyAddress');
  const status = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  const visitors: Visitor[] = [];
  const contexts: BrowserContext[] = [];
  const apis: APIRequestContext[] = [];
  const epochs: string[] = [];
  const addresses: string[] = Object.values(ADDRESS).flat();
  try {
    // Row 1: five visitors, then the sixth.
    for (const address of ADDRESS.v.slice(0, 5)) visitors.push(await openVisitor(browser, address));
    const [first] = visitors as [Visitor];
    const start = await first.page.request.get(STATE);
    expect(start.status(), 'V1 has a session').toBe(200);
    const cursor: Cursor = { seq: ((await start.json()) as { streams: { session: number } }).streams.session };
    const turn = await postTurn(first.page.request, cursor, 1, 'online-visitors');
    expect(await readBoth(status), 'with five visitors signed in and polling neither form is busy, and neither carries the marker header').toEqual({ plain: NOT_BUSY, trace: NOT_BUSY });

    const sixth = await openVisitor(browser, ADDRESS.v[5]);
    visitors.push(sixth);
    expect(await sessionRowCount(), 'every visitor has its row').toBeGreaterThanOrEqual(6);
    expect(await readBoth(status), 'with the sixth in the plain status is busy with the marker header and 200, and the trace form is not busy and has no header').toEqual({
      plain: BUSY,
      trace: NOT_BUSY,
    });
    const fresh = await browser.newContext({ baseURL: process.env['OCUTALON_URL'] });
    contexts.push(fresh);
    await expectBusySplash(await fresh.newPage(), 'row 1, a fresh context');
    await signOutGroup(fresh);

    // Row 2: the seventh sees Demo busy before and after pressing Sign in and start.
    const seventh = await browser.newContext({ baseURL: process.env['OCUTALON_URL'], extraHTTPHeaders: { 'X-Forwarded-For': ADDRESS.seventh } });
    contexts.push(seventh);
    const seventhPage = await seventh.newPage();
    await expectBusySplash(seventhPage, 'row 2, before sign-in');
    const rowsBefore = await sessionRowCount();
    const refused = seventhPage.waitForResponse((response) => response.request().method() === 'POST');
    await seventhPage.getByRole('button', { name: 'Sign in and start', exact: true }).click();
    const answer = await refused;
    expect(answer.status(), 'row 2: the sign-in is answered with 200').toBe(200);
    expect(answer.headers()[BUSY_HEADER], 'row 2: with the marker header').toBe('1');
    await expect(seventhPage.locator('#ocu-error'), 'row 2: and the busy error').toContainText(DEMO_BUSY_TEXT);
    expect(await answer.text(), 'row 2: no shell').not.toContain('<app-root');
    await expect(seventhPage.locator('app-root'), 'row 2: the page holds no shell').toHaveCount(0);
    expect(await resumeCookie(seventh), 'row 2: no resume cookie').toBeUndefined();
    expect((await seventh.request.get(STATE)).status(), 'row 2: /state answers 401').toBe(401);
    expect(await sessionRowCount(), 'row 2: no Session row is made').toBe(rowsBefore);
    expect(await counterRows(ADDRESS.seventh), 'row 2: and no counter row for the address').toBe(0);
    await signOutGroup(seventh);

    // Row 3: the probe's path (a sign-in that is not proxied) is exempt.
    const direct = await (async () => {
      try {
        await setPublic('proxyAddress', UNUSED_PROXY);
        return await signInOverHttpFrom(playwright, ADDRESS.direct);
      } finally {
        await setPublic('proxyAddress', savedProxy);
      }
    })();
    apis.push(direct.api);
    expect(direct.answer.status(), 'row 3: the direct sign-in is answered with 200').toBe(200);
    expect(await direct.answer.text(), 'row 3: and gets the shell').toContain('<app-root');
    const directState = await direct.api.get(STATE);
    expect(directState.status(), 'row 3: /state answers 200').toBe(200);
    epochs.push(((await directState.json()) as { epoch: string }).epoch);
    expect(await counterRows(ADDRESS.direct), 'row 3: it writes no counter row').toBe(0);
    expect((await readStatus(status)).busy, 'row 3: the plain status is still busy with six counted visitors, and the direct sign-in is not a seventh').toBe(true);

    // Row 4: a sign-out leaves the count at once, while the direct sign-in is still signed in.
    await pressSignOut(sixth.page);
    await confirmSignOut(sixth.page);
    await landedOnSplash(sixth.page, 30_000);
    expect(await readStatus(status), 'row 4: the plain status is not busy at the first read after V6 lands on the splash').toEqual(NOT_BUSY);
    expect((await direct.api.get(STATE)).status(), 'row 4: the direct sign-in is still signed in').toBe(200);
    await direct.api.get(SIGN_OUT);

    // Row 5: T, which makes no request after its one /state, is the sixth counted visitor; Visual Trace opens at the full house.
    const t = await signInOverHttpFrom(playwright, ADDRESS.t);
    apis.push(t.api);
    expect(t.answer.status(), 'row 5: T signs in').toBe(200);
    expect(await t.answer.text(), 'row 5: and gets the shell').toContain('<app-root');
    const tState = await t.api.get(STATE);
    expect(tState.status(), 'row 5: T has a session').toBe(200);
    epochs.push(((await tState.json()) as { epoch: string }).epoch);
    const lastRequest = Date.now();
    expect(await readBoth(status), 'row 5: at the full house the plain status is busy and the trace form is not').toEqual({ plain: BUSY, trace: NOT_BUSY });

    const asked: string[] = [];
    first.page.on('request', (request) => {
      if (new URL(request.url()).pathname === '/ocutalon/public/status') asked.push(request.url());
    });
    await first.page.getByRole('button', { name: 'Visual Trace', exact: true }).click();
    const menu = first.page.getByRole('dialog', { name: 'Visual Trace', exact: true });
    const conversation = menu.getByRole('link', { name: 'Open my conversation in Visual Trace (opens in a new tab)', exact: true });
    await expect(conversation, 'row 5: the menu links the turn').toHaveAttribute('href', turn.traceUrl);
    const opened = await opensTabStrict(first.context, () => conversation.click());
    await expectOpenedDirectly(opened, turn, 'row 5');
    await expect(first.page.locator(BANNER), 'row 5: no Demo busy banner shows').toHaveCount(0);
    expect(asked.length, 'row 5: the page asked the status').toBeGreaterThan(0);
    const check = new URL(asked[0] ?? 'http://stack.invalid/none');
    expect([...check.searchParams.keys()], 'row 5: with exactly the keys for and t').toEqual(['for', 't']);
    expect(check.searchParams.get('for'), 'row 5: for is trace').toBe('trace');
    expect(check.searchParams.get('t'), 'row 5: t is a time in milliseconds').toMatch(/^\d{13}$/);

    // Row 6: T leaves the count at its timeout, which another application's session does not move.
    const keepAlive = async (): Promise<void> => {
      await first.context.request.get(opened.popup.url()).catch(() => undefined);
    };
    await keepAlive();
    let lastKeep = Date.now();
    const tick = async (): Promise<void> => {
      await sleep(2000);
      if (Date.now() - lastKeep >= 30_000) {
        lastKeep = Date.now();
        await keepAlive();
      }
    };
    while (Date.now() - lastRequest < 110_000) await tick();
    expect((await readStatus(status)).busy, 'row 6: 110 s after T\'s last request the plain status still reports busy').toBe(true);
    let left = -1;
    while (Date.now() - lastRequest <= 140_000) {
      if (!(await readStatus(status)).busy) {
        left = Math.round((Date.now() - lastRequest) / 1000);
        break;
      }
      await tick();
    }
    console.log(`MEASURED V1: T left the count ${left} s after its last request`);
    expect(left, 'row 6: by 140 s the plain status reports not busy').toBeGreaterThan(0);
    expect(await liveTraceSessions(), 'row 6: while V1\'s trace session is still in the session store').toBeGreaterThanOrEqual(1);
    const late = await openVisitor(browser, ADDRESS.late);
    visitors.push(late);

    // Row 9: the query forms, at the full house again (V1 to V5 and the late visitor).
    const probe = `probe=${Date.now()}`;
    const forms: Array<{ query: string; busy: boolean }> = [
      { query: `for=trace&${probe}a`, busy: false },
      { query: `${probe}b`, busy: true },
      { query: `for=&${probe}c`, busy: true },
      { query: `for=Trace&${probe}d`, busy: true },
      { query: `for=trace%20&${probe}e`, busy: true },
      { query: `for=other&${probe}f`, busy: true },
      { query: `for=trace&for=trace&${probe}g`, busy: true },
      { query: `FOR=trace&${probe}h`, busy: true },
    ];
    for (const { query, busy } of forms) {
      const answered = await statusAnswer(status, query);
      expect(answered, `row 9: ?${query}`).toEqual({ code: 200, keys: KEYS, busy, header: busy ? '1' : undefined, setCookie: false });
    }
  } finally {
    for (const visitor of visitors) await leaveVisitor(visitor);
    for (const context of contexts) {
      await signOutGroup(context).catch(() => undefined);
      await context.close().catch(() => undefined);
    }
    for (const api of apis) {
      await api.get(SIGN_OUT).catch(() => undefined);
      await api.dispose().catch(() => undefined);
    }
    for (const epoch of epochs) await removeSession(epoch);
    for (const address of addresses) await removeCounterRows(address);
    await status.dispose();
    await setPublic('proxyAddress', savedProxy);
  }
});
