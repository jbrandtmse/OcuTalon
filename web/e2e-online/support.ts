import { createHash } from 'node:crypto';

import { expect, type APIRequestContext, type Browser, type BrowserContext, type Cookie, type Locator, type Page, type PlaywrightWorkerArgs, type Response } from '@playwright/test';

import { STATE } from '../e2e/support/api';
import { pageNow, runUntil } from '../e2e/support/clock';
import { chk, fixtureUser, irisScript, quoted } from '../e2e/support/iris';
import { loadedAfter } from '../e2e/support/floor';
import { drawnMessages, TRACE_PAGE, type Turn } from '../e2e/support/trace';
import { signInOverHttp } from '../e2e/sign-in/helpers';

/**
 * What the specs of web/e2e-online/ share: the online-demo, online-session, online-allowance, online-demo-path and online-visitors projects
 * (Stories 16.1, 16.4, 16.9, 29.4 and 29.7). Each project runs on the throwaway that its unit (docker/tests/test-online-demo.sh,
 * test-online-session.sh, test-online-allowance.sh, test-online-demo-path.sh or test-online-visitors.sh) starts with the online-demo flag on and the test start values; the unit gives the
 * two public accounts' names and passwords as OCUTALON_DEMOACCOUNT_* and OCUTALON_READONLYACCOUNT_* (fixtureUser reads them).
 */

/** The group-wide sign-out of the sign-in group: it ends the CSP session of /ocutalon, /ocutalon/api and the trace applications. */
export const SIGN_OUT = '/ocutalon/?IRISLogout=end';

/** The sign-out of each trace application, which signOutGroup also sends so that no trace session outlives the case. */
const TRACE_SIGN_OUTS = ['/ocutalon/trace/ocutalon/?IRISLogout=end', '/ocutalon/trace/ocuorders/?IRISLogout=end'] as const;

/**
 * Signs the context out of the whole sign-in group. Every spec calls it in `finally`, because a signed-in CSP session holds one of the
 * stack's licence connections until it times out (120 s on the online demo, Story 16.4, and only while nothing polls). A failed sign-out is
 * not a failure of the case.
 */
export async function signOutGroup(target: Page | BrowserContext): Promise<void> {
  const context = 'context' in target && typeof target.context === 'function' ? target.context() : (target as BrowserContext);
  for (const path of [SIGN_OUT, ...TRACE_SIGN_OUTS]) {
    try {
      await context.request.get(path);
    } catch {
      /* The context may be closed already. */
    }
  }
}

let probes = 0;
/** The address with a probe that no other request of the run used (the unit's test discipline: the web gateway keeps the answer to a URL). */
export const probed = (path: string): string => `${path}${path.includes('?') ? '&' : '?'}probe=${Date.now()}${(probes += 1)}`;
/** The splash's address with a fresh probe. */
const probedSplash = (): string => probed('/ocutalon/');

/**
 * Signs in from the splash at path (by default the splash with a fresh probe): it opens the page, fills a field only when its value is
 * given (the exact labels "User name" and "Password"; the fields are prefilled with the published values), presses **Sign in and
 * start** and returns the server's answer to the form. The caller then asserts what the next page shows, with an assertion that waits
 * for it.
 */
export async function signInFromSplash(page: Page, user?: string, password?: string, path = probedSplash()): Promise<Response> {
  await page.goto(path);
  if (user !== undefined) await page.getByLabel('User name', { exact: true }).fill(user);
  if (password !== undefined) await page.getByLabel('Password', { exact: true }).fill(password);
  const answered = page.waitForResponse((response) => response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Sign in and start', exact: true }).click();
  return answered;
}

/**
 * Waits until the page has gone to an address that url matches and has loaded it. The address must be one that only the page's own leaving
 * gives (`?since=`, `&ended=1`): a wait for an address that the page shows already returns at once. For the plain splash, use landedOnSplash.
 */
export async function landedOn(page: Page, url: Parameters<Page['waitForURL']>[0], timeout: number): Promise<void> {
  await page.waitForURL(url, { timeout, waitUntil: 'load' });
}

/**
 * Waits until the page has left the application for the plain splash, has loaded it and shows it at the plain address /ocutalon/, all
 * within timeout. The splash's sign-in form is what tells the two apart, not the address: the application drops the query it was opened
 * with and shows /ocutalon/#/, so a wait for the plain address returns before the page has left. The case's next navigation (a sign-in
 * from the splash) then meets the location.replace that the page still has to make once the server has answered /session/end, and that
 * replace aborts it (net::ERR_ABORTED).
 */
export async function landedOnSplash(page: Page, timeout: number): Promise<void> {
  const until = Date.now() + timeout;
  await expect(page.getByRole('button', { name: 'Sign in and start', exact: true }), 'the page has left for the splash').toBeVisible({ timeout });
  await page.waitForLoadState('load', { timeout: Math.max(1, until - Date.now()) });
  const landed = new URL(page.url());
  expect(landed.pathname + landed.search, 'the plain splash shows, at the plain address').toBe('/ocutalon/');
}

/** The epoch of the page's own /state (Story 16.4): the request carries the page's cookies. */
export async function epochOf(page: Pick<Page, 'request'>): Promise<string> {
  const response = await page.request.get(STATE);
  expect(response.status(), 'the state is served').toBe(200);
  return ((await response.json()) as { epoch: string }).epoch;
}

/** Signs the page in from the splash and returns its epoch, once the page has loaded its snapshot (loadedAfter: the answer of /state first, DW-333). */
export async function openSession(page: Page): Promise<string> {
  await loadedAfter(page, () => signInFromSplash(page));
  return epochOf(page);
}

/** How far advance moves the page's clock in one step: five seconds, so that the page makes and handles its polls on the way. */
const CLOCK_STEP_MS = 5000;

/** Moves the page's clock on by ms, in steps of CLOCK_STEP_MS (a clock that the case installed before the page loaded). */
export async function advance(page: Page, ms: number): Promise<void> {
  await runUntil(page, await pageNow(page), ms, CLOCK_STEP_MS);
}

/**
 * Opens a Visual Trace page of the OCUTALON trace application in a new tab of the context, at a fresh probe, checks that the page itself
 * was served (status 200 and no sign-in form), so that the context holds a trace CSP session, and closes the tab.
 */
export async function openTraceTab(context: BrowserContext): Promise<void> {
  const tab = await context.newPage();
  const response = await tab.goto(probed(`${TRACE_PAGE}1`), { waitUntil: 'domcontentloaded' });
  expect(response?.status(), 'the trace page is served').toBe(200);
  await expect(tab.locator('input[name=IRISUsername]'), 'with no sign-in form: the context holds a trace session').toHaveCount(0);
  await tab.close();
}

/** Opens the trace address in a new tab of the context, at a fresh probe, and checks that it shows the trace sign-in form. */
export async function expectTraceSignIn(context: BrowserContext, message: string): Promise<void> {
  const tab = await context.newPage();
  await tab.goto(probed(`${TRACE_PAGE}1`), { waitUntil: 'domcontentloaded' });
  await expect(tab.locator('input[name=IRISUsername]'), message).toBeVisible();
  await tab.close();
}

/**
 * Before the page's scripts run: records every text that the splash's one polite live region (#ocu-live) receives, each node added to
 * it, as window.announced, so that a case can count how often a message was announced. The CDK announcer's recorder of support/page.ts
 * does not see this region: it watches the announcer's own element.
 */
export async function recordSplashAnnouncements(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const announced: string[] = [];
    (window as unknown as { announced: string[] }).announced = announced;
    new MutationObserver((records) => {
      for (const record of records) {
        if (!(record.target instanceof HTMLElement) || record.target.id !== 'ocu-live') continue;
        for (const node of Array.from(record.addedNodes)) {
          if (node.textContent) announced.push(node.textContent);
        }
      }
    }).observe(document, { subtree: true, childList: true });
  });
}

/** The texts that the splash's live region received so far, in order (recordSplashAnnouncements). */
export function splashAnnouncements(page: Page): Promise<string[]> {
  return page.evaluate(() => [...((window as unknown as { announced?: string[] }).announced ?? [])]);
}

/** The name of the resume cookie that the sign-in sets (Story 16.3; OcuTalon.Web.SessionEvents.#RESUMECOOKIE). */
export const RESUME_COOKIE = 'OcuTalonResume';

/** The context's resume cookie, or undefined when it holds none. */
export async function resumeCookie(context: BrowserContext): Promise<Cookie | undefined> {
  return (await context.cookies()).find((cookie) => cookie.name === RESUME_COOKIE);
}

/** The SHA-256 of the text, base64url without padding: the form in which OcuTalon.Data.Session.Hash stores a resume reference (a client address is stored as an HMAC instead, AddressCounter.AddressHash). */
export function sha256url(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('base64url');
}

/** The fields of a Session row that a case reads (found by its epoch, which /state returns). */
export interface SessionRow {
  ref: string;
  traceRef: string;
  epoch: string;
  irisUser: string;
  resumeHash: string;
  cspSessionId: string;
}

/**
 * The Session row whose Epoch is the given one, read in the container, or undefined when there is none. The online demo has many rows
 * for one IRIS user, so a visitor's row is found by the epoch of its own /state, never by the user name.
 */
export async function sessionRow(epoch: string): Promise<SessionRow | undefined> {
  const lines = await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM OcuTalon_Data.Session WHERE Epoch = ?",${quoted(epoch)})`,
      'Set found=0 While rs.%Next() { Set r=##class(OcuTalon.Data.Session).%OpenId(rs.%Get("ID")) If $IsObject(r),r.Epoch=' + quoted(epoch) + ' { Set found=1 Quit } }',
      'Write !,"CHK|found|",found',
      'If found { Write !,"CHK|ref|",r.Ref,!,"CHK|trace|",r.TraceRef,!,"CHK|user|",r.IrisUser,!,"CHK|hash|",r.ResumeHash,!,"CHK|csp|",r.CspSessionId }',
    ].join('\n'),
  );
  if (chk(lines, 'found') !== '1') return undefined;
  return {
    ref: chk(lines, 'ref') ?? '',
    traceRef: chk(lines, 'trace') ?? '',
    epoch,
    irisUser: chk(lines, 'user') ?? '',
    resumeHash: chk(lines, 'hash') ?? '',
    cspSessionId: chk(lines, 'csp') ?? '',
  };
}

/**
 * Removes the Session row of an epoch with everything the test left on it: its turns and their decisions, its live events and
 * deliveries (Fixture.Clean), and the production messages of its trace thread. A case calls it in `finally` for each visitor it signed in.
 */
export async function removeSession(epoch: string): Promise<void> {
  await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM OcuTalon_Data.Session WHERE Epoch = ?",${quoted(epoch)})`,
      'While rs.%Next() { Set r=##class(OcuTalon.Data.Session).%OpenId(rs.%Get("ID")) If $IsObject(r),r.Epoch=' +
        quoted(epoch) +
        ' { Set ss=[] Do ss.%Push(r.TraceRef) Do ##class(OcuTalon.Test.Data.Fixture).Adopt(r) Set refs=##class(OcuTalon.Test.Data.Fixture).AdoptTurns(r.Ref,r.Ref) Do ##class(OcuTalon.Test.Data.Fixture).Clean(refs) Do ##class(OcuTalon.Test.Data.Fixture).RemoveMessages(ss) } }',
      'Write !,"CHK|removed|1"',
    ].join('\n'),
  );
}

/** A visitor of the online demo: its own browser context, signed in at the splash, and its session's identity. */
export interface Visitor {
  context: BrowserContext;
  page: Page;
  epoch: string;
  /** The session's Ref and its TraceRef (the tag of its production messages). */
  ref: string;
  trace: string;
}

/**
 * Opens a new browser context on the stack, signs the demo account in from the splash and waits for the page's snapshot (loadedAfter), and
 * returns the visitor with its session row's Ref and TraceRef. With an address, every request of the context carries it as X-Forwarded-For,
 * so that a proxied stack counts the visitor under it (Story 29.7). With pageOptions the context takes that time zone and locale, which
 * the page writes its times in (the steps 2 to 5 of the online run use UTC and en-GB, as the web run does). A visitor that cannot be opened is signed out and closed before the
 * error goes on. The caller ends it with leaveVisitor.
 */
export async function openVisitor(browser: Browser, address?: string, pageOptions: { timezoneId?: string; locale?: string } = {}): Promise<Visitor> {
  const context = await browser.newContext({
    baseURL: process.env['OCUTALON_URL'],
    ...pageOptions,
    ...(address === undefined ? {} : { extraHTTPHeaders: { 'X-Forwarded-For': address } }),
  });
  try {
    const page = await context.newPage();
    await loadedAfter(page, () => signInFromSplash(page));
    const epoch = await epochOf(page);
    const row = await sessionRow(epoch);
    if (row === undefined) throw new Error(`the session of epoch ${epoch} has no row`);
    return { context, page, epoch, ref: row.ref, trace: row.traceRef };
  } catch (error) {
    await signOutGroup(context);
    await context.close().catch(() => undefined);
    throw error;
  }
}

/** Signs a visitor out of the sign-in group, removes its session and closes its context; a visitor that was never opened is skipped. */
export async function leaveVisitor(visitor: Visitor | undefined): Promise<void> {
  if (visitor === undefined) return;
  await signOutGroup(visitor.context);
  await removeSession(visitor.epoch);
  await visitor.context.close();
}

/**
 * Signs the demo account in over HTTP from a client that the proxy would see as the address: an API context whose requests carry
 * X-Forwarded-For, at the splash with a fresh probe. It returns the context (the caller signs it out with SIGN_OUT and disposes it)
 * and the answer to the sign-in.
 */
export async function signInOverHttpFrom(playwright: PlaywrightWorkerArgs['playwright'], address: string): Promise<{ api: APIRequestContext; answer: Awaited<ReturnType<typeof signInOverHttp>> }> {
  const api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'], extraHTTPHeaders: { 'X-Forwarded-For': address } });
  const { user, password } = fixtureUser('DEMOACCOUNT');
  return { api, answer: await signInOverHttp(api, user, password, probedSplash()) };
}

/** The busy text of the splash, the host's busy page and the page's "Demo busy" banner (catalog key banner.demoBusy), written out as the oracle of the page's own. */
export const DEMO_BUSY_TEXT = 'The demo is busy right now. Try again in a few minutes, or install it yourself.';

/** The marker header of every busy answer that IRIS renders (OcuTalon.Web.Public.Status.#BUSYHEADER). */
export const BUSY_HEADER = 'x-ocutalon-busy';

let publicProbes = 0;

/** The value of a public setting (OcuTalon.Data.Public.Settings), read in the container; "" when it is unset. */
export async function publicValue(key: string): Promise<string> {
  const lines = await irisScript(`Write !,"CHK|value|",##class(OcuTalon.Data.Public.Settings).Get(${quoted(key)})`);
  return chk(lines, 'value') ?? '';
}

/** Sets a public setting in the container and reads it back; it throws when the read-back differs, so that a cap is never left unrestored unseen. */
export async function setPublic(key: string, value: string): Promise<void> {
  const lines = await irisScript(
    [`Do ##class(OcuTalon.Data.Public.Settings).Set(${quoted(key)},${quoted(value)})`, `Write !,"CHK|value|",##class(OcuTalon.Data.Public.Settings).Get(${quoted(key)})`].join('\n'),
  );
  const read = chk(lines, 'value');
  if (read !== value) throw new Error(`the public setting ${key} reads '${read ?? '<nothing>'}' after it was set to '${value}'`);
}

/** What /ocutalon/public/status answered: its busy value, the marker header (undefined when absent) and the status code. */
export interface StatusReading {
  busy: boolean;
  header: string | undefined;
  code: number;
}

/**
 * GET /ocutalon/public/status, in its trace form (`for=trace`) when form is 'trace', with a query that no other request of the run used,
 * so that no cache answers; the request carries no session.
 */
export async function readStatus(api: APIRequestContext, form?: 'trace'): Promise<StatusReading> {
  publicProbes += 1;
  const response = await api.get(`/ocutalon/public/status?${form === 'trace' ? 'for=trace&' : ''}probe=${Date.now()}${publicProbes}`);
  const body = (await response.json()) as { busy: boolean };
  return { busy: body.busy, header: response.headers()[BUSY_HEADER], code: response.status() };
}

/** What GET /ocutalon/public/status answered to a query: its status code, the parsed body's keys, busy, the marker header and whether it set a cookie. */
export interface StatusAnswer {
  code: number;
  keys: string[];
  busy: boolean | undefined;
  header: string | undefined;
  setCookie: boolean;
}

/** GET /ocutalon/public/status with the query as given (it carries the probe the run needs: pass it in the query), and the answer's parts. */
export async function statusAnswer(api: APIRequestContext, query: string): Promise<StatusAnswer> {
  const response = await api.get(`/ocutalon/public/status?${query}`);
  const body = (await response.json()) as Record<string, unknown>;
  return {
    code: response.status(),
    keys: Object.keys(body),
    busy: typeof body['busy'] === 'boolean' ? body['busy'] : undefined,
    header: response.headers()[BUSY_HEADER],
    setCookie: response.headers()['set-cookie'] !== undefined,
  };
}

/** The AddressCounter rows of an address (the table holds its hash). */
export async function counterRows(address: string): Promise<number> {
  const lines = await irisScript(
    `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?",##class(OcuTalon.Data.AddressCounter).AddressHash(${quoted(address)})) Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)`,
  );
  return Number(chk(lines, 'rows') ?? '-1');
}

/** Removes the AddressCounter rows of an address, so that a case's sign-ins leave no trace on the address limit. */
export async function removeCounterRows(address: string): Promise<void> {
  await irisScript(
    `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.AddressCounter WHERE AddressHash = ?",##class(OcuTalon.Data.AddressCounter).AddressHash(${quoted(address)}))\nWrite !,"CHK|dropped|1"`,
  );
}

/** The number of Session rows; a count that cannot be read throws, so that two failed reads never compare equal. */
export async function sessionRowCount(): Promise<number> {
  const lines = await irisScript('Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.Session") Do rs.%Next() Write !,"CHK|rows|",rs.%GetData(1)');
  const rows = chk(lines, 'rows') ?? '';
  if (!/^[0-9]+$/.test(rows)) throw new Error(`the Session rows could not be counted (read '${rows}')`);
  return Number(rows);
}

/** The page's trace check asks the status with exactly the keys for (trace) and t (a time in milliseconds, so that no cache answers). */
export function expectTraceQuery(check: URL, label: string): void {
  expect([...check.searchParams.keys()], `${label}: the query holds exactly for and t`).toEqual(['for', 't']);
  expect(check.searchParams.get('for'), `${label}: for is trace`).toBe('trace');
  expect(check.searchParams.get('t'), `${label}: t is a time in milliseconds`).toMatch(/^\d{13}$/);
}

/**
 * The HTTP view of the instance's licence connections: what the connection check of /ocutalon/public/status counts, which is one less than
 * the count that an iris_script reads (its own process holds one). It is found by the flip of Task 0 (a) on the status's trace form, whose
 * busy comes from the connection check alone (so live visitors never move it): with r the script's count, the cap is set to r plus the
 * reserve, and a busy status means the view is r, otherwise it is r - 1 (checked with the cap at r - 1 plus the reserve). The cap is put
 * back to what it was and read back, on every path. `api` must carry no session.
 */
export async function httpConnections(api: APIRequestContext): Promise<number> {
  const savedCap = await publicValue('connectionCap');
  const reserve = Number(await publicValue('connectionReserve'));
  if (!Number.isInteger(reserve)) throw new Error('connectionReserve is not a whole number');
  const count = chk(await irisScript('Write !,"CHK|r|",$SYSTEM.License.InstanceConnections()'), 'r');
  const r = Number(count);
  if (!Number.isInteger(r)) throw new Error(`InstanceConnections() read '${count ?? '<nothing>'}'`);
  try {
    await setPublic('connectionCap', String(r + reserve));
    if ((await readStatus(api, 'trace')).busy) return r;
    await setPublic('connectionCap', String(r - 1 + reserve));
    if (!(await readStatus(api, 'trace')).busy) throw new Error(`the HTTP view of the connections is neither ${r} nor ${r - 1}`);
    return r - 1;
  } finally {
    await setPublic('connectionCap', savedCap);
  }
}

/** True when a CSP session with the id exists in the container (read through irisScript in %SYS-wide terms: the session extent is the instance's). */
export async function cspSessionExists(id: string): Promise<boolean> {
  const lines = await irisScript(`Write !,"CHK|exists|",##class(%CSP.Session).%ExistsId(${quoted(id)})`);
  return chk(lines, 'exists') === '1';
}

/** What a case watches for in a page: whether any node of the document held the text. It outlives the page's navigations. */
export interface TextWatch {
  seen: () => boolean;
}

/**
 * Before the page's scripts run: records, through an exposed function that survives navigations, whether any node of any document of the
 * page ever held the text (a MutationObserver over the whole document, checked at every change). A case uses it to show that the page never
 * showed a text that must not reach it.
 */
export async function watchText(page: Page, text: string): Promise<TextWatch> {
  let seen = false;
  await page.exposeFunction('__ocuSeenText', () => {
    seen = true;
  });
  await page.addInitScript((needle) => {
    const check = (): void => {
      if (document.documentElement?.textContent?.includes(needle)) (window as unknown as { __ocuSeenText: () => void }).__ocuSeenText();
    };
    new MutationObserver(check).observe(document, { subtree: true, childList: true, characterData: true });
  }, text);
  return { seen: () => seen };
}

/** The URLs of every request of a context's pages, in order (a request context such as page.request does not show here). */
export interface RequestLog {
  /** The number of requests so far, a mark for `since`. */
  mark: () => number;
  /** The URLs requested after the mark. */
  since: (mark: number) => string[];
}

/** Records the URL of every request of the context's pages. */
export function recordRequests(context: BrowserContext): RequestLog {
  const urls: string[] = [];
  context.on('request', (request) => urls.push(request.url()));
  return { mark: () => urls.length, since: (mark) => urls.slice(mark) };
}

/** The rows that populate() made for a session, by their Refs ('' when none). */
export interface Populated {
  session: string;
  reminder: string;
  approval: string;
  pairing: string;
}

/** What populate() makes besides the reminder: the watch (default true), the pending approval request (default true) and the fixture pairing (a display name; default "Dana"; false for none). */
export interface PopulateOptions {
  watch?: boolean;
  approval?: boolean;
  pairing?: string | false;
}

/**
 * Gives the session (a Ref) a real reminder due in an hour (ReminderFixture) and, unless the options leave them out, a real watch of the
 * Orders production (a StartWatch through Commands.Submit, as the page's chat tool does), a pending approval request that the demo account
 * may answer and a fixture pairing, and returns their Refs ('' for what was left out). A case calls cleanPopulated for it in `finally`.
 */
export async function populate(session: string, options: PopulateOptions = {}): Promise<Populated> {
  const { watch = true, approval: withApproval = true, pairing: withPairing = 'Dana' } = options;
  const lines = await irisScript(
    [
      `Set ref=${quoted(session)}`,
      'Set made=##class(OcuTalon.Test.Schedule.ReminderFixture).Set(ref,"zz sign out",3600)',
      'Write !,"CHK|reminder|",made.ref,"|",made.ok',
      ...(watch
        ? [
            'Set start=##class(OcuTalon.Msg.Command.StartWatch).%New() Set start.SessionRef=ref,start.Namespace=##class(OcuTalon.Install.Step.Demo).#NAMESPACE,start.Production=##class(OcuTalon.Install.Step.Demo).#PRODUCTION,start.DisplayName="Orders"',
            'Set sc=##class(OcuTalon.Core.Commands).Submit(start,"web_user",.started)',
            'Write !,"CHK|watch|",$Select($IsObject($Get(started)):started.Ok_"|"_started.Outcome,1:"none")',
          ]
        : []),
      ...(withApproval ? ['Write !,"CHK|approval|",##class(OcuTalon.Test.Data.Fixture).Approval(ref,"","pending",,{"RequiredRole":"OcuTalonUser"})'] : []),
      ...(withPairing !== false ? [`Write !,"CHK|pairing|",##class(OcuTalon.Test.Data.Fixture).Pairing(ref,${quoted(withPairing)})`] : []),
    ].join('\n'),
  );
  const reminder = (chk(lines, 'reminder') ?? '').split('|');
  if (reminder[1] !== '1' || (watch && chk(lines, 'watch') !== '1|started')) throw new Error(`the session's reminder and watch could not be made: ${lines.join(' ')}`);
  return { session, reminder: reminder[0] ?? '', approval: chk(lines, 'approval') ?? '', pairing: chk(lines, 'pairing') ?? '' };
}

/** The failed orders that Break the feed sent under a TraceRef: the messages that reached OrdersFromPartner in a failed state of the Orders production (OCUORDERS). */
export async function ordersOf(trace: string): Promise<number> {
  const lines = await irisScript(`Write !,"CHK|orders|",##class(OcuTalon.Test.Demo.Production).Count(${quoted(trace)},"OrdersFromPartner",8)`);
  return Number(chk(lines, 'orders') ?? '-1');
}

/** The tab that the action opens, with the answers of every trace document recorded: a sign-in field in any of them is a failure. */
export async function opensTabStrict(context: BrowserContext, action: () => Promise<unknown>): Promise<{ popup: Page; signInPages: string[] }> {
  const signInPages: string[] = [];
  const watch = async (response: Response): Promise<void> => {
    if (response.request().resourceType() !== 'document' || !response.url().includes('/ocutalon/trace/')) return;
    const body = await response.text().catch(() => '');
    if (/name=["']?IRISPassword/.test(body)) signInPages.push(response.url());
  };
  context.on('response', (response) => void watch(response));
  const [popup] = await Promise.all([context.waitForEvent('page'), action()]);
  await popup.waitForLoadState('domcontentloaded');
  return { popup, signInPages };
}

/** The tab is at the link's traceUrl (its path and session), shows no sign-in field and draws the turn. */
export async function expectOpenedDirectly(opened: { popup: Page; signInPages: string[] }, turn: Turn, label: string): Promise<void> {
  const { popup, signInPages } = opened;
  const want = new URL(turn.traceUrl, 'http://stack.invalid');
  await expect.poll(() => new URL(popup.url()).pathname, { message: `${label}: the tab is at the link's page`, timeout: 30_000 }).toBe(want.pathname);
  expect(new URL(popup.url()).searchParams.get('SESSIONID'), `${label}: and at the link's session`).toBe(want.searchParams.get('SESSIONID'));
  const drawn = await drawnMessages(popup);
  expect(drawn.ids, `${label}: Visual Trace draws the turn`).toContain(String(turn.traceHeaderId));
  await expect(popup.locator('input[name=IRISPassword]'), `${label}: no sign-in field`).toHaveCount(0);
  expect(signInPages, `${label}: no document of the tab was a sign-in page`).toEqual([]);
}

/** What a session's populated rows read now. */
export interface PopulatedState {
  reminder: string;
  waiting: number;
  watches: number;
  approval: string;
  pairing: string;
  resumeHash: string;
}

/** Reads the state of a session's populated rows in the container: the rows' states, the reminder's waiters, the watch rows and the pairing. */
export async function populatedState(rows: Populated): Promise<PopulatedState> {
  const lines = await irisScript(
    [
      `Write !,"CHK|reminder|",##class(OcuTalon.Data.Reminder).RefIndexOpen(${quoted(rows.reminder)}).State`,
      `Write !,"CHK|waiting|",##class(OcuTalon.Test.Schedule.ReminderFixture).WaitingCount(${quoted(rows.reminder)})`,
      `Write !,"CHK|watches|",##class(OcuTalon.Data.Ownership).Checks(${quoted(rows.session)}).Count()`,
      `Write !,"CHK|approval|",##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(${quoted(rows.approval)}).State`,
      `Set p=##class(OcuTalon.Data.Ownership).Pairing(${quoted(rows.session)},.sc) Write !,"CHK|pairing|",$Select($IsObject(p):p.SessionRef,1:"")`,
      `Write !,"CHK|hash|",##class(OcuTalon.Data.Session).RefIndexOpen(${quoted(rows.session)}).ResumeHash`,
    ].join('\n'),
  );
  return {
    reminder: chk(lines, 'reminder') ?? '',
    waiting: Number(chk(lines, 'waiting') ?? '-1'),
    watches: Number(chk(lines, 'watches') ?? '-1'),
    approval: chk(lines, 'approval') ?? '',
    pairing: chk(lines, 'pairing') ?? '',
    resumeHash: chk(lines, 'hash') ?? '',
  };
}

/** The mark of the audit log now (AuditLog.Now), for auditEntries. */
export async function auditMark(): Promise<string> {
  return chk(await irisScript('Write !,"CHK|mark|",##class(OcuTalon.Test.Bridge.AuditLog).Now()'), 'mark') ?? '';
}

/** How many audit entries of the type, written since the mark, name the marker (a Ref), and, for a Pairing entry, hold `summary` as change/reason/channel. */
export async function auditCount(mark: string, type: 'Approval' | 'Pairing', marker: string, summary: string): Promise<number> {
  const lines = await irisScript(
    [
      `Set es=##class(OcuTalon.Test.Bridge.AuditLog).Entries(${quoted(mark)},"OcuTalon",${quoted(type)},${quoted(type)},${quoted(marker)})`,
      'Set n=0 For i=0:1:es.%Size()-1 { Set d=es.%Get(i).data If d.change_"/"_$Select(d.%IsDefined("reason"):d.reason,1:"")_"/"_d.channel=' + quoted(summary) + ' Set n=n+1 }',
      'Write !,"CHK|count|",n',
    ].join('\n'),
  );
  return Number(chk(lines, 'count') ?? '-1');
}

/** Removes what populate() made, with the reminder's waiter and the watch rows; the session's own rows are removeSession's. */
export async function cleanPopulated(rows: Populated): Promise<void> {
  await irisScript(
    [
      `Do ##class(OcuTalon.Test.Schedule.ReminderFixture).RemoveAll(${quoted(rows.session)})`,
      `Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.BackgroundCheck WHERE SessionRef = ?",${quoted(rows.session)})`,
      `Do ##class(OcuTalon.Test.Data.Fixture).Clean(${quoted(`${rows.approval},${rows.pairing}`)})`,
      'Write !,"CHK|cleaned|1"',
    ].join('\n'),
  );
}

/** A turn of the session whose text is given, made directly (Fixture.Turn); removeSession removes it with the session. */
export async function fixtureTurn(session: string, text: string): Promise<void> {
  await irisScript([`Do ##class(OcuTalon.Test.Data.Fixture).Turn(${quoted(session)},,,${quoted(text)})`, 'Write !,"CHK|turn|1"'].join('\n'));
}

/** The online demo's Sign out dialog: its one sentence, which names it. Written out as the independent oracle of the page's own. */
export const SIGN_OUT_SENTENCE = 'Signing out ends this demo session. Signing in again starts a fresh one.';

/** The account menu's trigger: a button named by the signed-in demo account. */
export const accountTrigger = (page: Page): Locator => page.getByRole('button', { name: fixtureUser('DEMOACCOUNT').user, exact: true });

/** The Sign out dialog. */
export const signOutDialog = (page: Page): Locator => page.getByRole('dialog', { name: SIGN_OUT_SENTENCE, exact: true });

/** Opens the account menu and chooses Sign out; the dialog opens. */
export async function pressSignOut(page: Page): Promise<void> {
  await accountTrigger(page).click();
  await page.getByRole('menuitem', { name: 'Sign out', exact: true }).click();
  await expect(signOutDialog(page)).toBeVisible();
}

/** Presses Sign out in the open dialog. */
export async function confirmSignOut(page: Page): Promise<void> {
  await signOutDialog(page).getByRole('button', { name: 'Sign out', exact: true }).click();
}

/** The script lines that put the Session row of an epoch in `r` ("" when there is none); the online demo has many rows for one user. */
function findSession(epoch: string): string {
  return [
    `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM OcuTalon_Data.Session WHERE Epoch = ?",${quoted(epoch)})`,
    `Set r="" While rs.%Next() { Set c=##class(OcuTalon.Data.Session).%OpenId(rs.%Get("ID")) If $IsObject(c),c.Epoch=${quoted(epoch)} { Set r=c Quit } }`,
  ].join('\n');
}

/** The allowance fields of a session's row (Story 16.9): how many messages it counts, the end of its window and the day of its daily-cap message. */
export interface AllowanceRow {
  ref: string;
  times: number;
  until: string;
  dailyCapDay: string;
}

/** Reads the allowance fields of the row of an epoch. */
export async function allowanceRow(epoch: string): Promise<AllowanceRow> {
  const lines = await irisScript(
    [findSession(epoch), 'If $IsObject(r) { Write !,"CHK|row|",r.Ref,"|",$ListLength(r.AllowanceTimes),"|",r.AllowanceUntil,"|",r.DailyCapDay }'].join('\n'),
  );
  const row = chk(lines, 'row');
  if (row === undefined) throw new Error(`the session of epoch ${epoch} has no row`);
  const [ref = '', times = '0', until = '', dailyCapDay = ''] = row.split('|');
  return { ref, times: Number(times), until, dailyCapDay };
}

/**
 * Gives the session of an epoch `count` accepted messages one second apart, the oldest being `oldestAge` seconds old, and no window: the
 * rolling hour of its allowance as if it had sent them. A case with 50 entries about 3580 s old is refused its next message with a retryAt
 * about 20 s ahead.
 */
export async function seedAllowance(epoch: string, count: number, oldestAge: number): Promise<void> {
  const lines = await irisScript(
    [
      findSession(epoch),
      `Set now=##class(OcuTalon.Data.Time).NowUtc() Set list="" For i=0:1:${count - 1} { Set list=list_$ListBuild(##class(OcuTalon.Data.Time).AddSeconds(now,i-${oldestAge})) }`,
      'Set r.AllowanceTimes=list Set r.AllowanceUntil="" Set sc=r.%Save()',
      'Write !,"CHK|saved|",$SYSTEM.Status.IsOK(sc)',
    ].join('\n'),
  );
  if (chk(lines, 'saved') !== '1') throw new Error(`the allowance of epoch ${epoch} could not be seeded (${lines.join(' ')})`);
}

/** The Turn rows of the session of an epoch, oldest first: their state, ClientId and text. */
export async function turnRowsOf(epoch: string): Promise<Array<{ state: string; clientId: string; text: string }>> {
  const lines = await irisScript(
    [
      findSession(epoch),
      'Set t=##class(%SQL.Statement).%ExecDirect(,"SELECT State, ClientId, Text FROM OcuTalon_Data.Turn WHERE SessionRef = ? ORDER BY ID",r.Ref)',
      'While t.%Next() { Write !,"CHK|turn|",t.%Get("State"),"|",t.%Get("ClientId"),"|",t.%Get("Text") }',
    ].join('\n'),
  );
  return lines
    .filter((line) => line.startsWith('CHK|turn|'))
    .map((line) => {
      const [state = '', clientId = '', ...text] = line.slice('CHK|turn|'.length).split('|');
      return { state, clientId, text: text.join('|') };
    });
}

/** Gives the session of an epoch `count` incoming mailbox emails one second apart, the oldest `oldestAge` seconds old (Fixture rows; removeSession removes them). */
export async function seedIncomingMail(epoch: string, count: number, oldestAge: number): Promise<void> {
  const lines = await irisScript(
    [
      findSession(epoch),
      `Set now=##class(OcuTalon.Data.Time).NowUtc() For i=0:1:${count - 1} { Do ##class(OcuTalon.Test.Data.Fixture).SimMessage(r.Ref,{"Kind":"mailbox","Direction":"in","Subject":"zz seeded","Text":"zz seeded","CreatedAt":(##class(OcuTalon.Data.Time).AddSeconds(now,i-${oldestAge}))}) }`,
      'Write !,"CHK|seeded|1"',
    ].join('\n'),
  );
  if (chk(lines, 'seeded') !== '1') throw new Error(`the emails of epoch ${epoch} could not be seeded (${lines.join(' ')})`);
}

/** How many incoming mailbox emails, mailbox events and Items from SimMailboxIn to Intake (under the session's TraceRef) the session of an epoch has so far. */
export async function mailCounts(epoch: string): Promise<{ rows: number; events: number; items: number }> {
  const lines = await irisScript(
    [
      findSession(epoch),
      'Set m=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM OcuTalon_Data.SimMessage WHERE SessionRef = ? AND Kind = ? AND Direction = ?",r.Ref,"mailbox","in") Do m.%Next()',
      'Set h=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE SuperSession = ? AND SourceConfigName = ? AND TargetConfigName = ? AND Type = 1",r.TraceRef,"SimMailboxIn","Intake") Do h.%Next()',
      'Write !,"CHK|counts|",m.%GetData(1),"|",##class(OcuTalon.Test.Core.Observe).Events(r.Ref,"mailbox").%Size(),"|",h.%GetData(1)',
    ].join('\n'),
  );
  const [rows = '-1', events = '-1', items = '-1'] = (chk(lines, 'counts') ?? '').split('|');
  return { rows: Number(rows), events: Number(events), items: Number(items) };
}

/** The fallback reasons of the bridge's decisions of the session of an epoch (Bridge.Data.Decision rows with Fallback set), oldest first. */
export async function fallbackReasons(epoch: string): Promise<string[]> {
  const lines = await irisScript(
    [
      findSession(epoch),
      'Set t=##class(%SQL.Statement).%ExecDirect(,"SELECT FallbackReason FROM OcuTalon_Bridge_Data.Decision WHERE OwnerRef = ? AND Fallback = 1 ORDER BY ID",r.Ref)',
      'While t.%Next() { Write !,"CHK|fallback|",t.%Get("FallbackReason") }',
    ].join('\n'),
  );
  return lines.filter((line) => line.startsWith('CHK|fallback|')).map((line) => line.slice('CHK|fallback|'.length));
}

/**
 * Whether StatusMonitor remembers the daily cap as lifted: the newest dailyCap status event of the instance stream is a clear, or there is
 * none. The monitor publishes a condition only when it changes, and what it remembers is what it last published.
 */
export async function dailyCapSettled(): Promise<boolean> {
  const lines = await irisScript(
    [
      'Set t=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 Payload FROM OcuTalon_Live.Event WHERE Stream = ? AND Type = ? AND Payload [ ? ORDER BY Seq DESC","instance","status","""condition"":""dailyCap""")',
      'Set p=$Select(t.%Next():t.%Get("Payload"),1:"")',
      `Write !,"CHK|settled|",(p="")||(p'["""active"":true")`,
    ].join('\n'),
  );
  return chk(lines, 'settled') === '1';
}

/**
 * The instance's local date (as the bridge keys the day's cap and a session records its daily-cap day) and the whole seconds left of it.
 * The day comes from one NowUtc and the seconds from the clock read just after it, so a midnight between the two reads gives a negative
 * count, which clearOfMidnight treats as too few seconds left.
 */
export interface InstanceDay {
  day: string;
  secondsLeft: number;
}

/** Reads the instance's day and the seconds left before it ends (Bridge.Time: LocalDate of NowUtc, then SecondsUntil its DayEndUtc). */
export async function instanceDay(): Promise<InstanceDay> {
  const lines = await irisScript(
    [
      'Set now=##class(OcuTalon.Bridge.Time).NowUtc() Set day=##class(OcuTalon.Bridge.Time).LocalDate(now)',
      'Write !,"CHK|day|",day,"|",##class(OcuTalon.Bridge.Time).SecondsUntil(##class(OcuTalon.Bridge.Time).DayEndUtc(day))',
    ].join('\n'),
  );
  const [day = '', left = ''] = (chk(lines, 'day') ?? '').split('|');
  const secondsLeft = Number(left);
  if (day === '' || left === '' || !Number.isFinite(secondsLeft)) throw new Error(`the instance day could not be read (${lines.join(' ')})`);
  return { day, secondsLeft };
}

/**
 * Returns the instance's day once at least budgetS seconds of it are left (DW-413). A case of the daily cap marks, checks and cleans up by
 * one day, so it must not start so near instance midnight that the day turns inside it: when fewer than budgetS seconds are left, this
 * waits past midnight (secondsLeft plus 2 s, through `sleep`) and reads again. `read` and `sleep` are injectable for the browserless
 * case that pins the guard.
 */
export async function clearOfMidnight(
  budgetS: number,
  read: () => Promise<InstanceDay> = instanceDay,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
): Promise<string> {
  const reading = await read();
  if (reading.secondsLeft >= budgetS) return reading.day;
  await sleep((reading.secondsLeft + 2) * 1000);
  return (await read()).day;
}

/** The key of a day's capped mark of the bridge, as an ObjectScript reference. */
const cappedKey = (day: string): string => `^OcuTalonBP.UsageCapped(${quoted(day)})`;

/** Whether the capped mark of the day (a date from instanceDay or clearOfMidnight) is set (^OcuTalonBP.UsageCapped(day)). */
export async function cappedMarked(day: string): Promise<boolean> {
  return chk(await irisScript(`Write !,"CHK|mark|",$Data(${cappedKey(day)})`), 'mark') !== '0';
}

/** Kills the capped mark of the day and returns whether it is gone. */
export async function unmarkCapped(day: string): Promise<boolean> {
  return chk(await irisScript(`Kill ${cappedKey(day)} Write !,"CHK|mark|",$Data(${cappedKey(day)})`), 'mark') === '0';
}

/**
 * Seeds a Usage row of `amount` US dollars for today (Fixture.Usage, owner instance) and returns its decision Ref, which
 * Fixture.Clean removes it with. IRIS's own count of the day's spend then reaches the cap (the daily cost cap is $20).
 */
export async function seedUsage(amount: number): Promise<string> {
  const lines = await irisScript(
    [
      'Set d=##class(OcuTalon.Bridge.Ids).NewRef()',
      `Do ##class(OcuTalon.Test.Data.Fixture).Usage(d,"instance",{"CostUSD":${amount}})`,
      'Write !,"CHK|usage|",d',
    ].join('\n'),
  );
  const ref = chk(lines, 'usage');
  if (!ref) throw new Error(`the Usage row could not be seeded (${lines.join(' ')})`);
  return ref;
}

/** Deletes the Usage row that seedUsage made. */
export async function removeUsage(ref: string): Promise<void> {
  await irisScript(`Do ##class(OcuTalon.Test.Data.Fixture).Clean(${quoted(ref)}) Write !,"CHK|removed|1"`);
}

/** The number of lines of the CI mock's request log that name the text (the log of the mock service, mounted in the container). */
export async function mockRequests(text: string): Promise<number> {
  const lines = await irisScript(
    [
      'Set n=0 Set f=##class(%Stream.FileCharacter).%New() Set sc=f.LinkToFile("/opt/ocutalon/mock-log/requests.jsonl")',
      `If $SYSTEM.Status.IsOK(sc) { While 'f.AtEnd { Set l=f.ReadLine() If l[${quoted(text)} Set n=n+1 } }`,
      'Write !,"CHK|requests|",n',
    ].join('\n'),
  );
  return Number(chk(lines, 'requests') ?? '-1');
}

/** Answers the session's approval request through the bridge's own API (Approval.Answer) as the demo account; returns its result (done, ...). */
export async function answerApproval(sessionRef: string, ref: string, action: 'approve' | 'reject'): Promise<string> {
  const lines = await irisScript(
    [
      `Set r=##class(OcuTalon.Bridge.Approval).Answer(${quoted(ref)},${quoted(action)},"web",${quoted(fixtureUser('DEMOACCOUNT').user)},${quoted(sessionRef)},.w,"OcuTalon.Bridge.Ext.HostSink")`,
      'Write !,"CHK|answer|",r',
    ].join('\n'),
  );
  return chk(lines, 'answer') ?? '';
}
