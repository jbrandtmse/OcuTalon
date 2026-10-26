import { randomBytes } from 'node:crypto';

import { expect, test, type Page } from '@playwright/test';

import { notBuilt } from '../e2e/demo-path/not-built';
import { EVENTS, holdState, MESSAGES, post, sessionEvents, STATE } from '../e2e/support/api';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted } from '../e2e/support/iris';
import { postTurn, signInToTrace, type Cursor } from '../e2e/support/trace';
import { RESUME_COOKIE, removeSession, resumeCookie, sessionRow, sha256url, signInFromSplash, signOutGroup, SIGN_OUT } from './support';

/**
 * Story 16.3, the visitor's own session and the resume cookie on the online-demo throwaway (R1, R2, R4, R5; matrix rows 1, 2, 5 and 7).
 * Every case is the DEMOACCOUNT (the unit's test start values), finds its visitor's Session row by the epoch of its own /state (the
 * demo account has many rows, so never by the user name), removes the rows it made and signs out of the whole sign-in group in
 * `finally`. The unit's first phase has the proxy address at a value no request comes from, so every sign-in here is exempt from the
 * address limit.
 * - R1: the first sign-in sets OcuTalonResume (22 base64url characters, the next reset as its expiry, HttpOnly, Secure, SameSite
 *   strict, path /ocutalon/), the browser keeps it, one new row stores only its SHA-256, and the page opens on an empty chat.
 * - R2: after the group sign-out, and coming from another site (which sends no Strict cookie to the splash), the same browser's
 *   sign-in resumes the row: the same epoch, its turn, its approval request, no new Session row, and its pairing and break-the-feed
 *   run still named by its Ref; skeletons show while /state is held. (Build 154 may reuse the CSP session id, so the attach of the
 *   new CSP session is pinned in process, by Test.Web.SessionEvents.TestResume.)
 * - R4: a cookie that names no row gives a new session and a new cookie.
 * - R5: two browsers get two sessions: A's turns, events and a body or query that names B's Ref never reach B, and the second turn is A's;
 *   a context that signed in only at the trace application has no session for the API (it never gets the shared account's row).
 * The texts are written out here, as the independent oracle of the page's own. A cookie value is a resume reference, so it is compared
 * as a boolean and never handed to an assertion that would print it.
 */
test.describe.configure({ timeout: 180_000 });

const KIND = 'DEMOACCOUNT';
const REFERENCE = /^[A-Za-z0-9_-]{22}$/;
let probes = 0;
const probed = (path: string): string => `${path}${path.includes('?') ? '&' : '?'}probe=${Date.now()}r${(probes += 1)}`;

const mainOf = (page: Page) => page.locator('main.main');
const rail = (page: Page) => page.locator('section.rail');

/** The /state of the page's own session: its epoch and the chat's JSON text. */
async function readState(page: Pick<Page, 'request'>): Promise<{ epoch: string; chat: string; session: number }> {
  const response = await page.request.get(STATE);
  expect(response.status(), 'the state is served').toBe(200);
  const state = (await response.json()) as { epoch: string; chat: unknown; streams: { session: number } };
  return { epoch: state.epoch, chat: JSON.stringify(state.chat), session: state.streams.session };
}

/** The number of Session rows, read in the container (the project runs one case at a time). */
async function sessionCount(): Promise<string> {
  return chk(await irisScript('Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Session")\nDo rs.%Next()\nWrite !,"CHK|rows|",rs.%GetData(1)'), 'rows') ?? '';
}

/** A new, valid-looking resume reference that no row has: 16 random bytes as base64url. */
const unknownReference = (): string => randomBytes(16).toString('base64url');

/** R1: the first sign-in sets the cookie, creates the row that stores only its hash, and opens an empty chat. */
test('R1: the first sign-in sets the resume cookie and opens a session of its own on an empty chat', async ({ page, context }) => {
  let epoch = '';
  try {
    const answered = await signInFromSplash(page);
    const headers = await answered.allHeaders();
    const cookieLine = (headers['set-cookie'] ?? '').split('\n').find((line) => line.startsWith(`${RESUME_COOKIE}=`)) ?? '';
    expect(cookieLine, "the sign-in POST's answer sets the resume cookie").not.toBe('');
    const value = cookieLine.slice(RESUME_COOKIE.length + 1).split(';')[0];
    expect(REFERENCE.test(value), 'its value is 22 base64url characters').toBe(true);
    const attributes = cookieLine.split(';').slice(1).map((part) => part.trim().toLowerCase());
    expect(attributes, 'HttpOnly').toContain('httponly');
    expect(attributes, 'Secure').toContain('secure');
    expect(attributes, 'SameSite strict').toContain('samesite=strict');
    expect(attributes, 'path /ocutalon/').toContain('path=/ocutalon/');
    const status = (await (await page.request.get(probed('/ocutalon/public/status'))).json()) as { nextReset: string };
    const nextReset = new Date(status.nextReset);
    expect(cookieLine.toLowerCase(), 'it expires at the next reset, as an RFC 1123 GMT date').toContain(`expires=${nextReset.toUTCString().toLowerCase()}`);

    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(page.locator('app-chat-panel app-empty-chat'), 'the main page opens on an empty chat').toHaveCount(1);
    await expect(page.locator('app-chat-panel app-user-message'), 'and no turn').toHaveCount(0);

    const kept = await resumeCookie(context);
    expect(kept, 'the browser keeps the cookie').toBeDefined();
    expect(kept!.value === value, "and it is the answer's value").toBe(true);
    expect(kept!.httpOnly, 'HttpOnly').toBe(true);
    expect(kept!.secure, 'Secure').toBe(true);
    expect(kept!.sameSite, 'SameSite Strict').toBe('Strict');
    expect(kept!.path, 'path').toBe('/ocutalon/');
    expect(Math.floor(kept!.expires), 'it expires at the next reset').toBe(Math.floor(nextReset.getTime() / 1000));
    console.log(`MEASURED Chromium keeps the Secure resume cookie over ${new URL(process.env['OCUTALON_URL']!).origin}: yes`);

    epoch = (await readState(page)).epoch;
    const row = await sessionRow(epoch);
    expect(row, "one new Session row is found by /state's epoch").toBeDefined();
    expect(row!.ref, 'a new Ref').toMatch(REFERENCE);
    expect(row!.traceRef, 'a new TraceRef').toMatch(REFERENCE);
    expect(row!.ref).not.toBe(row!.traceRef);
    expect(row!.irisUser.toLowerCase(), "the demo account's row").toBe(fixtureUser(KIND).user.toLowerCase());
    expect(row!.resumeHash, 'it stores the SHA-256 of the cookie value').toBe(sha256url(value));
    expect(row!.cspSessionId, 'and the CSP session').not.toBe('');
    expect([row!.ref, row!.traceRef, row!.epoch, row!.irisUser, row!.resumeHash, row!.cspSessionId].includes(value), 'no property equals the cookie value').toBe(false);
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** R2: the same browser resumes its session after its CSP session ended, also when it comes from another site. */
test('R2: the same browser signs in again and resumes its conversation, approval request and orders', async ({ page, context }) => {
  let epoch = '';
  let fixtures: string[] = [];
  let runId = '';
  try {
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    epoch = (await readState(page)).epoch;
    const first = (await sessionRow(epoch))!;
    expect(first, 'the first sign-in made a row').toBeDefined();
    const cookie = (await resumeCookie(context))!;
    expect(cookie, 'with a cookie').toBeDefined();

    const text = `zz resume turn ${Date.now().toString(36)}`;
    const seeded = await irisScript(
      [
        `Set t=##class(OcuTalon.Test.Data.Fixture).Turn(${quoted(first.ref)},,"done",${quoted(text)})`,
        `Set a=##class(OcuTalon.Test.Data.Fixture).Approval(${quoted(first.ref)})`,
        `Set p=##class(OcuTalon.Test.Data.Fixture).Pairing(${quoted(first.ref)})`,
        `Set b=##class(OcuTalon.Data.BreakFeedRun).%New() Set b.SessionRef=${quoted(first.ref)} Set b.State="sent" Set b.StartedAt=##class(OcuTalon.Data.Time).NowUtc() Set sc=b.%Save()`,
        'Write !,"CHK|turn|",t,!,"CHK|approval|",a,!,"CHK|pairing|",p,!,"CHK|run|",$Select($SYSTEM.Status.IsOK(sc):b.%Id(),1:"")',
      ].join('\n'),
    );
    fixtures = [chk(seeded, 'turn') ?? '', chk(seeded, 'approval') ?? '', chk(seeded, 'pairing') ?? ''];
    runId = chk(seeded, 'run') ?? '';
    expect(fixtures.every((ref) => ref !== '') && runId !== '', `the fixture rows are seeded (${seeded.join(' ')})`).toBe(true);

    await signOutGroup(page);
    expect((await page.request.get(STATE)).status(), 'the CSP session ended').toBe(401);
    expect((await resumeCookie(context))?.value === cookie.value, 'and the cookie stays').toBe(true);
    const rowsBefore = await sessionCount();
    expect(rowsBefore, 'the Session rows are counted').toMatch(/^[0-9]+$/);

    await context.route('http://elsewhere.test/**', (route) =>
      route.fulfill({ contentType: 'text/html', body: `<!doctype html><title>elsewhere</title><a id="go" href="${new URL(probed('/ocutalon/'), process.env['OCUTALON_URL']).href}">go</a>` }),
    );
    const sent: Array<{ method: string; cookie: string }> = [];
    page.on('request', (request) => {
      if (new URL(request.url()).pathname === '/ocutalon/') void request.allHeaders().then((headers) => sent.push({ method: request.method(), cookie: headers['cookie'] ?? '' }));
    });
    await page.goto('http://elsewhere.test/');
    await page.locator('#go').click();
    await expect(page.getByRole('button', { name: 'Sign in and start', exact: true })).toBeVisible();
    await expect.poll(() => sent.some((one) => one.method === 'GET'), { message: 'the splash GET was seen' }).toBe(true);
    expect(sent.find((one) => one.method === 'GET')!.cookie.includes(RESUME_COOKIE), 'the splash GET from another site carries no resume cookie').toBe(false);

    const hold = await holdState(page);
    const answered = page.waitForResponse((response) => response.request().method() === 'POST');
    await page.getByRole('button', { name: 'Sign in and start', exact: true }).click();
    await answered;
    expect(sent.find((one) => one.method === 'POST')?.cookie, 'the sign-in POST carries the resume cookie').toContain(`${RESUME_COOKIE}=`);
    await expect.poll(() => hold.held(), { message: '/state is held' }).toBe(1);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loading');
    await expect(rail(page).locator('.skeleton-rows'), 'a group of skeleton rows in each rail section').toHaveCount(4);
    await expect(mainOf(page).locator('.skeleton-chat'), 'and the skeleton chat in main').toHaveCount(1);
    hold.release();
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');

    const after = await readState(page);
    expect(after.epoch, 'the same session: the same epoch').toBe(epoch);
    await expect(page.locator('app-chat-panel').getByText(text, { exact: true }), "the turn's text is in the chat").toBeVisible();
    await expect(rail(page).getByRole('heading', { level: 3 }).first(), 'the approval request is in the rail').toHaveAccessibleName('Approval requests, 1');
    const resumed = (await sessionRow(epoch))!;
    expect(resumed.ref, 'the epoch still names the first row').toBe(first.ref);
    expect(await sessionCount(), 'no new Session row').toBe(rowsBefore);
    expect(resumed.traceRef, 'its TraceRef is unchanged').toBe(first.traceRef);
    expect(resumed.resumeHash, 'its hash is unchanged').toBe(first.resumeHash);
    expect((await resumeCookie(context))?.value === cookie.value, 'the resume sets no new cookie').toBe(true);
    const owners = await irisScript(
      [
        `Write !,"CHK|pairing|",##class(OcuTalon.Data.Pairing).RefIndexOpen(${quoted(fixtures[2])}).SessionRef`,
        `Write !,"CHK|run|",##class(OcuTalon.Data.BreakFeedRun).%OpenId(${quoted(runId)}).SessionRef`,
      ].join('\n'),
    );
    expect(chk(owners, 'pairing'), 'the pairing still names the row').toBe(first.ref);
    expect(chk(owners, 'run'), "and so does the Break the feed run, whose orders carry the row's TraceRef").toBe(first.ref);
  } finally {
    await signOutGroup(page);
    await cleanFixtureRows(fixtures);
    if (runId && /^[0-9]+$/.test(runId)) await irisScript(`Do ##class(OcuTalon.Data.BreakFeedRun).%DeleteId(${runId})\nWrite !,"CHK|run|1"`);
    if (epoch) await removeSession(epoch);
  }
});

notBuilt('R2b: /state returns the fixture pairing', '10.3');
notBuilt("R2c: the rail's Telegram card shows the fixture pairing", '12.7');

/** R4: a cookie that names no row gives a new session and a new cookie, and the old value's hash opens no row. */
test('R4: an unknown resume cookie gives a fresh session and a new cookie', async ({ page, context }) => {
  let epoch = '';
  try {
    const unknown = unknownReference();
    await context.addCookies([{ name: RESUME_COOKIE, value: unknown, domain: new URL(process.env['OCUTALON_URL']!).hostname, path: '/ocutalon/', httpOnly: true, secure: true, sameSite: 'Strict' }]);
    expect((await resumeCookie(context))?.value, 'the context holds the unknown cookie').toBe(unknown);
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    epoch = (await readState(page)).epoch;
    const row = await sessionRow(epoch);
    expect(row, 'a new session has its own row').toBeDefined();
    const fresh = await resumeCookie(context);
    expect(REFERENCE.test(fresh?.value ?? ''), 'a new cookie is set').toBe(true);
    expect(fresh!.value !== unknown, 'with a different value').toBe(true);
    expect(row!.resumeHash, "the row stores the new value's hash").toBe(sha256url(fresh!.value));
    const opened = await irisScript(`Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Session WHERE ResumeHash = ?",${quoted(sha256url(unknown))})\nDo rs.%Next()\nWrite !,"CHK|opens|",rs.%GetData(1)`);
    expect(chk(opened, 'opens'), "the old value's hash opens no row").toBe('0');
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** R5: two browsers on the demo account get two sessions, and a SessionRef in a request never selects another's. */
test('R5: two browsers each get their own session, and no request chooses another visitor', async ({ browser }) => {
  const a = await browser.newContext();
  const b = await browser.newContext();
  const pageA = await a.newPage();
  const pageB = await b.newPage();
  const epochs: string[] = [];
  try {
    await signInFromSplash(pageA);
    await signInFromSplash(pageB);
    await expect(mainOf(pageA)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(mainOf(pageB)).toHaveAttribute('data-snapshot', 'loaded');
    const stateA = await readState(pageA);
    const stateB = await readState(pageB);
    epochs.push(stateA.epoch, stateB.epoch);
    expect(stateA.epoch, 'two epochs').not.toBe(stateB.epoch);
    const cookieA = (await resumeCookie(a))!.value;
    const cookieB = (await resumeCookie(b))!.value;
    expect(cookieA !== cookieB, 'two cookie values').toBe(true);
    const rowB = (await sessionRow(stateB.epoch))!;
    expect(rowB, "B's row is found").toBeDefined();

    const cursorA: Cursor = { seq: stateA.session };
    const turn = await postTurn(pageA.request, cursorA, 1, 'online-resume');
    expect((await readState(pageA)).chat, "A's chat shows the turn").toContain(turn.clientId);
    const eventsA = await sessionEvents(pageA.request, stateA.session, (seen) => seen.some((event) => event.payload['clientId'] === turn.clientId), 5);
    expect(eventsA.length, "A's events show the turn").toBeGreaterThan(0);
    expect((await readState(pageB)).chat, "B's chat shows none of A's turn").not.toContain(turn.clientId);
    const eventsB = await sessionEvents(pageB.request, stateB.session, () => false, 3);
    expect(JSON.stringify(eventsB), "B's events after its cursor show none of A's").not.toContain(turn.clientId);

    const second = `zz-online-resume-${Date.now().toString(36)}-2`;
    const sentTwice = await post(pageA.request, `${MESSAGES}?sessionRef=${encodeURIComponent(rowB.ref)}`, { clientId: second, text: 'zz online-resume turn 2', fromGuide: false, sessionRef: rowB.ref });
    expect(sentTwice.status(), 'a body and a query that name B are ignored: the post is accepted as A\'s').toBe(202);
    const eventsSecond = await sessionEvents(pageA.request, cursorA.seq, (seen) => seen.some((event) => event.payload['clientId'] === second && event.payload['state'] === 'done'), 30);
    expect(
      eventsSecond.some((event) => event.payload['clientId'] === second),
      "the second turn is A's",
    ).toBe(true);
    expect((await readState(pageB)).chat, "B's chat shows none of the second turn").not.toContain(second);
    const eventsB2 = await sessionEvents(pageB.request, stateB.session, () => false, 2);
    expect(JSON.stringify(eventsB2), "B's events show none of the second turn").not.toContain(second);
    const idle = await pageB.request.get(`${EVENTS}?after=${stateB.session}&afterInstance=0&sessionRef=${encodeURIComponent((await sessionRow(stateA.epoch))!.ref)}`);
    expect(JSON.stringify(await idle.json()), "B's poll with A's Ref in the query still shows none of A's events").not.toContain(turn.clientId);

    const carried = await browser.newContext();
    try {
      const traceOnly = await carried.newPage();
      await traceOnly.goto(probed('/ocutalon/trace/ocutalon/EnsPortal.MessageViewer.zen'));
      await signInToTrace(traceOnly, KIND);
      await expect(traceOnly, 'the trace application signed in').toHaveTitle(/Message Viewer/, { timeout: 30_000 });
      const unattached = await carried.request.get(STATE);
      expect(unattached.status(), 'a sign-in that only the trace application carried has no OcuTalon session, and the API never takes the shared account\'s row for it').toBeGreaterThanOrEqual(400);
    } finally {
      await signOutGroup(carried);
      await carried.close();
    }
  } finally {
    for (const context of [a, b]) {
      await context.request.get(SIGN_OUT).catch(() => undefined);
      await signOutGroup(context);
      await context.close();
    }
    for (const epoch of epochs) await removeSession(epoch);
  }
});
