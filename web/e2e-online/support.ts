import { createHash } from 'node:crypto';

import type { APIRequestContext, BrowserContext, Cookie, Page, PlaywrightWorkerArgs, Response } from '@playwright/test';

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
 * stack's licence connections until it times out (28,800 s on a throwaway). A failed sign-out is not a failure of the case.
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
