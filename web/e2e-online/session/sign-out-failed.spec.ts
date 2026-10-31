import { expect, test, type Page } from '@playwright/test';

import { STATE } from '../../e2e/support/api';
import { loadedAfter } from '../../e2e/support/floor';
import { chk, irisScript, quoted } from '../../e2e/support/iris';
import {
  cleanPopulated,
  confirmSignOut,
  epochOf,
  populate,
  pressSignOut,
  recordRequests,
  removeSession,
  resumeCookie,
  sessionRow,
  signInFromSplash,
  signOutGroup,
  type Populated,
} from '../support';

/**
 * Story 16.4, a Sign out that really fails (matrix row 11; AC 5), on the throwaway of docker/tests/test-online-session.sh. O3 fakes the
 * 500; this case makes SessionOps.End fail for real: the session's reminder row is held open by a background job (Test.Web.HeldReminder), so
 * ReminderOps cannot cancel it and the EndSession is answered failed.
 * - O4: the demo account signs in, and its session gets a fixture pairing, a real reminder, a real Orders watch and a pending approval request.
 *   With the reminder held, Sign out is confirmed: /session/end answers 500 server_error and sets no cookie, the page signs the group out,
 *   shows the plain splash and keeps the resume cookie; every other step ran (the watch is gone, the request cancelled, the chat unlinked)
 *   but the reminder is still pending and the row still holds the same resume hash. Signing in again resumes the same epoch. With the row
 *   free, Sign out again is 204 and expires the cookie; the reminder is cancelled, the hash is cleared and the next sign-in gives a new epoch.
 * The case signs out of the whole sign-in group, lets go of the held row and removes its rows in `finally`.
 */
test.describe.configure({ timeout: 240_000 });

const mainOf = (page: Page) => page.locator('main.main');

/** Starts the job that holds the reminder's row (concurrency 4) and waits until it does; true when it holds it. */
async function holdReminder(ref: string): Promise<boolean> {
  const lines = await irisScript(`Write !,"CHK|held|",##class(OcuTalon.Test.Web.HeldReminder).Start(${quoted(ref)},150)`);
  return chk(lines, 'held') === '1';
}

/** Asks the job to let go of the reminder's row and waits until it has; true when it is done or was never started. */
async function releaseReminder(ref: string): Promise<boolean> {
  const lines = await irisScript(`Write !,"CHK|released|",##class(OcuTalon.Test.Web.HeldReminder).Release(${quoted(ref)})`);
  return chk(lines, 'released') === '1';
}

/** What the session's rows read now. The reminder is read by SQL, which takes no lock, because the held row would make a keyed open wait. */
async function stateOf(rows: Populated): Promise<{ reminder: string; watches: number; approval: string; pairing: string; resumeHash: string }> {
  const lines = await irisScript(
    [
      `Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT State FROM OcuTalon_Data.Reminder WHERE Ref = ?",${quoted(rows.reminder)}) Set state="" If rs.%Next() { Set state=rs.%Get("State") }`,
      'Write !,"CHK|reminder|",state',
      `Write !,"CHK|watches|",##class(OcuTalon.Data.Ownership).Checks(${quoted(rows.session)}).Count()`,
      `Write !,"CHK|approval|",##class(OcuTalon.Bridge.Data.ApprovalRequest).RefIndexOpen(${quoted(rows.approval)}).State`,
      `Set p=##class(OcuTalon.Data.Ownership).Pairing(${quoted(rows.session)},.sc) Write !,"CHK|pairing|",$Select($IsObject(p):p.SessionRef,1:"")`,
      `Write !,"CHK|hash|",##class(OcuTalon.Data.Session).RefIndexOpen(${quoted(rows.session)}).ResumeHash`,
    ].join('\n'),
  );
  return {
    reminder: chk(lines, 'reminder') ?? '',
    watches: Number(chk(lines, 'watches') ?? '-1'),
    approval: chk(lines, 'approval') ?? '',
    pairing: chk(lines, 'pairing') ?? '',
    resumeHash: chk(lines, 'hash') ?? '',
  };
}

/** The Set-Cookie lines of a response that name the resume cookie. */
async function resumeCookieLines(response: { allHeaders: () => Promise<Record<string, string>> }): Promise<string[]> {
  return ((await response.allHeaders())['set-cookie'] ?? '').split('\n').filter((line) => line.startsWith('OcuTalonResume='));
}

test('O4: a Sign out that fails for real keeps the session resumable, and the repeat with the row free finishes the work', async ({ page, context }) => {
  const epochs: string[] = [];
  let rows: Populated | undefined;
  let held = '';
  let release = (): void => undefined;
  try {
    const log = recordRequests(context);
    await loadedAfter(page, () => signInFromSplash(page));
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    const epoch = await epochOf(page);
    epochs.push(epoch);
    const row = (await sessionRow(epoch))!;
    expect(row.resumeHash, "the row holds a resume hash").not.toBe('');
    rows = await populate(row.ref);
    held = rows.reminder;
    expect(await holdReminder(rows.reminder), 'another process holds the reminder row').toBe(true);

    const mark = log.mark();
    // The page leaves once its group sign-out has answered, and leaving drops the 500's body: the sign-out waits until the body is read.
    const reading = new Promise<void>((resolve) => {
      release = resolve;
    });
    await page.route(/IRISLogout=end/, async (route) => {
      await reading;
      await route.continue().catch(() => undefined);
    });
    const failed = page.waitForResponse((response) => response.url().includes('/ocutalon/api/v1/session/end'), { timeout: 120_000 });
    await pressSignOut(page);
    await confirmSignOut(page);
    const response = await failed;
    expect(response.status(), '/session/end answers 500').toBe(500);
    const body = (await response.json()) as { error: { code: string } };
    const failedCookies = await resumeCookieLines(response);
    release();
    expect(body.error.code, 'server_error').toBe('server_error');
    expect(failedCookies, 'and sets no cookie').toEqual([]);

    await expect(page.getByRole('button', { name: 'Sign in and start', exact: true }), 'the plain splash shows').toBeVisible({ timeout: 60_000 });
    const landed = new URL(page.url());
    expect(landed.pathname + landed.search, 'at the plain address').toBe('/ocutalon/');
    expect(log.since(mark).some((url) => /\/ocutalon\/\?IRISLogout=end&t=/.test(url)), 'after the page signed the group out with a request').toBe(true);
    expect((await context.request.get(STATE)).status(), "the context's CSP session is gone").toBe(401);
    expect(await resumeCookie(context), 'the resume cookie is kept').toBeDefined();

    const partial = await stateOf(rows);
    expect(partial.reminder, 'the held reminder is still pending').toBe('pending');
    expect(partial.watches, 'the watch is stopped').toBe(0);
    expect(partial.approval, 'the request is cancelled').toBe('cancelled');
    expect(partial.pairing, 'the chat is unlinked').toBe('');
    expect(partial.resumeHash, 'and the row holds the same resume hash').toBe(row.resumeHash);

    expect(await releaseReminder(rows.reminder), 'the row is let go').toBe(true);
    held = '';
    await loadedAfter(page, () => signInFromSplash(page));
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    expect(await epochOf(page), 'signing in resumes the same session').toBe(epoch);

    await pressSignOut(page);
    const ended = page.waitForResponse((response) => response.url().includes('/ocutalon/api/v1/session/end'), { timeout: 120_000 });
    await confirmSignOut(page);
    const done = await ended;
    expect(done.status(), 'the repeat answers 204').toBe(204);
    const cookies = await resumeCookieLines(done);
    expect(cookies.length, 'and expires the resume cookie once').toBe(1);
    expect(cookies[0]!.split(';')[0], 'to the empty value').toBe('OcuTalonResume=');
    await expect(page.getByRole('button', { name: 'Sign in and start', exact: true }), 'the plain splash shows').toBeVisible({ timeout: 60_000 });
    expect(await resumeCookie(context), 'the browser holds no resume cookie').toBeUndefined();
    await expect.poll(async () => (await stateOf(rows!)).reminder, { message: 'the reminder is cancelled', timeout: 30_000 }).toBe('cancelled');
    expect((await stateOf(rows)).resumeHash, 'and the resume hash is cleared').toBe('');

    await loadedAfter(page, () => signInFromSplash(page));
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    const next = await epochOf(page);
    epochs.push(next);
    expect(next, 'the next sign-in gives a new epoch').not.toBe(epoch);
  } finally {
    release();
    if (held) await releaseReminder(held);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (rows) await cleanPopulated(rows);
    for (const epoch of epochs) await removeSession(epoch);
  }
});
