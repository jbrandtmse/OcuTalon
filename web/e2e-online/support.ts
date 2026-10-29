import { createHash } from 'node:crypto';

import { expect, type APIRequestContext, type BrowserContext, type Cookie, type Locator, type Page, type PlaywrightWorkerArgs, type Response } from '@playwright/test';

import { chk, fixtureUser, irisScript, quoted } from '../e2e/support/iris';
import { signInOverHttp } from '../e2e/sign-in/helpers';

/**
 * What the specs of the online-demo project share (Story 16.1). The project runs on the throwaway that docker/tests/test-online-demo.sh
 * starts with the online-demo flag on and the test start values; the unit gives the two public accounts' names and passwords as
 * OCUTALON_DEMOACCOUNT_* and OCUTALON_READONLYACCOUNT_* (fixtureUser reads them).
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
/** The splash's address with a probe that no other request of the run used (the unit's test discipline). */
const probedSplash = (): string => `/ocutalon/?probe=${Date.now()}${(probes += 1)}`;

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

/** The SHA-256 of the text, base64url without padding: the form in which OcuTalon.Data.Session.Hash stores a reference or an address. */
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

/** GET /ocutalon/public/status with a query that no other request of the run used, so that no cache answers; the request carries no session. */
export async function readStatus(api: APIRequestContext): Promise<StatusReading> {
  publicProbes += 1;
  const response = await api.get(`/ocutalon/public/status?probe=${Date.now()}${publicProbes}`);
  const body = (await response.json()) as { busy: boolean };
  return { busy: body.busy, header: response.headers()[BUSY_HEADER], code: response.status() };
}

/**
 * The HTTP view of the instance's licence connections: what /ocutalon/public/status counts, which is one less than the count that an
 * iris_script reads (its own process holds one). It is found by the flip of Task 0 (a): with r the script's count, the cap is set to
 * r plus the reserve, and a busy status means the view is r, otherwise it is r - 1 (checked with the cap at r - 1 plus the reserve). The
 * cap is put back to what it was and read back, on every path. `api` must carry no session.
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
    if ((await readStatus(api)).busy) return r;
    await setPublic('connectionCap', String(r - 1 + reserve));
    if (!(await readStatus(api)).busy) throw new Error(`the HTTP view of the connections is neither ${r} nor ${r - 1}`);
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

/**
 * Gives the session (a Ref) a real reminder due in an hour (ReminderFixture), a real watch of the Orders production (a StartWatch through
 * Commands.Submit, as the page's chat tool does), a pending approval request that the demo account may answer and a fixture pairing, and
 * returns their Refs. A case calls cleanPopulated for it in `finally`.
 */
export async function populate(session: string): Promise<Populated> {
  const lines = await irisScript(
    [
      `Set ref=${quoted(session)}`,
      'Set made=##class(OcuTalon.Test.Schedule.ReminderFixture).Set(ref,"zz sign out",3600)',
      'Set start=##class(OcuTalon.Msg.Command.StartWatch).%New() Set start.SessionRef=ref,start.Namespace=##class(OcuTalon.Install.Step.Demo).#NAMESPACE,start.Production=##class(OcuTalon.Install.Step.Demo).#PRODUCTION,start.DisplayName="Orders"',
      'Set sc=##class(OcuTalon.Core.Commands).Submit(start,"web_user",.started)',
      'Set approval=##class(OcuTalon.Test.Data.Fixture).Approval(ref,"","pending",,{"RequiredRole":"OcuTalonUser"})',
      'Set pair=##class(OcuTalon.Test.Data.Fixture).Pairing(ref,"Dana")',
      'Write !,"CHK|reminder|",made.ref,"|",made.ok,!,"CHK|watch|",$Select($IsObject($Get(started)):started.Ok_"|"_started.Outcome,1:"none"),!,"CHK|approval|",approval,!,"CHK|pairing|",pair',
    ].join('\n'),
  );
  const reminder = (chk(lines, 'reminder') ?? '').split('|');
  if (reminder[1] !== '1' || chk(lines, 'watch') !== '1|started') throw new Error(`the session's reminder and watch could not be made: ${lines.join(' ')}`);
  return { session, reminder: reminder[0] ?? '', approval: chk(lines, 'approval') ?? '', pairing: chk(lines, 'pairing') ?? '' };
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
