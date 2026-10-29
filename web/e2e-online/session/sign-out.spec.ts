import { expect, test, type Page } from '@playwright/test';

import { STATE } from '../../e2e/support/api';
import { TRACE_PAGE } from '../../e2e/support/trace';
import {
  accountTrigger,
  auditCount,
  auditMark,
  cleanPopulated,
  confirmSignOut,
  populate,
  populatedState,
  pressSignOut,
  recordRequests,
  removeSession,
  resumeCookie,
  sessionRow,
  signInFromSplash,
  signOutDialog,
  signOutGroup,
  type Populated,
} from '../support';

/**
 * Story 16.4, Sign out on the online demo (matrix rows 10 and 11), on the throwaway of docker/tests/test-online-session.sh.
 * - O1 (row 10, AC 5): the account menu's Sign out opens a modal dialog named by its one sentence, with exactly the buttons Cancel and Sign
 *   out; Cancel has the focus, Tab and Shift+Tab stay inside, and Esc, Cancel and a press on the backdrop close it with no request to
 *   /session/end, the same epoch and the focus back on the account trigger.
 * - O2 (row 11, AC 5 and 6; DW-291, DW-285): two sessions, each with a fixture pairing, a real reminder, a real Orders watch and a pending
 *   approval request; the first opens a trace page and closes it, then presses Sign out and confirms. /session/end answers 204 and expires
 *   the resume cookie, the plain splash shows with no notice, the first session's reminder is cancelled (its waiter ended, through the real
 *   ReminderOps), its watch is gone (the real WatchOps), its request cancelled with an Approval entry, its pairing unlinked with an
 *   audit entry (unlinked, session_end, web), its resume hash cleared and its trace address needs a sign-in; the second session's rows are
 *   unchanged; and the first one's next sign-in gives a new epoch.
 * - O3 (AC 5): a /session/end that fails (500): the page signs the group out with a request, not a navigation, lands on the plain splash
 *   address and the session stays resumable: the resume cookie is kept and signing in again gives the same epoch.
 * Every case signs out of the whole sign-in group and removes its rows in `finally`.
 */
test.describe.configure({ timeout: 240_000 });

const mainOf = (page: Page) => page.locator('main.main');

/** The epoch of the page's own /state. */
async function epochOf(page: Pick<Page, 'request'>): Promise<string> {
  const response = await page.request.get(STATE);
  expect(response.status(), 'the state is served').toBe(200);
  return ((await response.json()) as { epoch: string }).epoch;
}

/** O1: the dialog. */
test('O1: Sign out opens a modal dialog named by its sentence, with Cancel focused; Esc, Cancel and the backdrop close it and change nothing', async ({ page, context }) => {
  let epoch = '';
  try {
    const log = recordRequests(context);
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    epoch = await epochOf(page);
    const mark = log.mark();
    const dialog = signOutDialog(page);

    await pressSignOut(page);
    await expect(dialog, 'a modal dialog').toHaveAttribute('aria-modal', 'true');
    await expect(page.locator('[role=dialog]'), 'exactly one dialog').toHaveCount(1);
    await expect(dialog.getByRole('button'), 'exactly the buttons Cancel and Sign out').toHaveText(['Cancel', 'Sign out']);
    await expect(dialog.getByRole('button', { name: 'Cancel', exact: true }), 'Cancel has the focus').toBeFocused();
    for (const key of ['Tab', 'Tab', 'Tab', 'Shift+Tab', 'Shift+Tab', 'Shift+Tab']) {
      await page.keyboard.press(key);
      expect(await page.evaluate(() => !!document.activeElement?.closest('[role=dialog]')), `${key}: the focus stays inside the dialog`).toBe(true);
    }
    await page.keyboard.press('Escape');
    await expect(dialog, 'Esc closes it').toHaveCount(0);
    await expect(accountTrigger(page), 'and the focus is back on the account trigger').toBeFocused();

    await pressSignOut(page);
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(dialog, 'Cancel closes it').toHaveCount(0);
    await expect(accountTrigger(page), 'and the focus is back on the account trigger').toBeFocused();

    await pressSignOut(page);
    await page.locator('.app-dialog-scrim').click({ position: { x: 4, y: 4 } });
    await expect(dialog, 'a press on the backdrop closes it').toHaveCount(0);
    await expect(accountTrigger(page), 'and the focus is back on the account trigger').toBeFocused();

    expect(log.since(mark).filter((url) => url.includes('/session/end') || url.includes('IRISLogout')), 'no request ended the session').toEqual([]);
    expect(await epochOf(page), 'the same epoch').toBe(epoch);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  } finally {
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});

/** O2: Sign out ends the session; another session is untouched. */
test('O2: confirming Sign out ends the session through SessionOps.End and leaves another session untouched', async ({ browser }) => {
  const contextA = await browser.newContext();
  const contextB = await browser.newContext();
  const pageA = await contextA.newPage();
  const pageB = await contextB.newPage();
  const epochs: string[] = [];
  const populated: Populated[] = [];
  try {
    await signInFromSplash(pageA);
    await expect(mainOf(pageA)).toHaveAttribute('data-snapshot', 'loaded');
    const epochA = await epochOf(pageA);
    epochs.push(epochA);
    await signInFromSplash(pageB);
    await expect(mainOf(pageB)).toHaveAttribute('data-snapshot', 'loaded');
    const epochB = await epochOf(pageB);
    epochs.push(epochB);
    const rowA = (await sessionRow(epochA))!;
    const rowB = (await sessionRow(epochB))!;
    expect(rowA.resumeHash, "A's row holds a resume hash").not.toBe('');
    const rowsA = await populate(rowA.ref);
    populated.push(rowsA);
    const rowsB = await populate(rowB.ref);
    populated.push(rowsB);

    const tab = await contextA.newPage();
    await tab.goto(`${TRACE_PAGE}1`, { waitUntil: 'domcontentloaded' });
    await tab.close();
    const mark = await auditMark();

    await pressSignOut(pageA);
    const answered = pageA.waitForResponse((response) => response.url().includes('/ocutalon/api/v1/session/end'));
    await confirmSignOut(pageA);
    const response = await answered;
    expect(response.status(), '/session/end answers 204').toBe(204);
    const cookies = ((await response.allHeaders())['set-cookie'] ?? '').split('\n').filter((line) => line.startsWith('OcuTalonResume='));
    expect(cookies.length, 'it sets the resume cookie once').toBe(1);
    expect(cookies[0]!.split(';')[0], 'to the empty value').toBe('OcuTalonResume=');
    expect(cookies[0]!.toLowerCase(), 'on the same path').toContain('path=/ocutalon/');
    expect(Date.parse(/expires=([^;]+)/i.exec(cookies[0]!)?.[1] ?? ''), 'expired').toBeLessThan(Date.now());

    await pageA.waitForURL((url) => url.pathname === '/ocutalon/' && url.search === '', { timeout: 60_000, waitUntil: 'commit' });
    await expect(pageA.getByRole('button', { name: 'Sign in and start', exact: true }), 'the plain splash shows').toBeVisible();
    await expect(pageA.locator('#ocu-notice'), 'with no notice').toHaveCount(0);
    expect(await resumeCookie(contextA), 'and the browser holds no resume cookie').toBeUndefined();

    await expect.poll(async () => (await populatedState(rowsA)).waiting, { message: "A's reminder has no waiter", timeout: 30_000 }).toBe(0);
    const stateA = await populatedState(rowsA);
    expect(stateA.reminder, "A's reminder is cancelled").toBe('cancelled');
    expect(stateA.watches, "A's watch row is gone").toBe(0);
    expect(stateA.approval, "A's request is cancelled").toBe('cancelled');
    expect(stateA.pairing, "A's pairing is unlinked").toBe('');
    expect(stateA.resumeHash, "A's resume hash is cleared").toBe('');
    await expect.poll(() => auditCount(mark, 'Approval', rowsA.approval, 'cancelled//web'), { message: 'an Approval entry cancelled', timeout: 20_000 }).toBe(1);
    await expect.poll(() => auditCount(mark, 'Pairing', rowsA.session, 'unlinked/session_end/web'), { message: 'a Pairing entry unlinked/session_end/web', timeout: 20_000 }).toBe(1);

    const trace = await contextA.newPage();
    await trace.goto(`${TRACE_PAGE}1`, { waitUntil: 'domcontentloaded' });
    await expect(trace.locator('input[name=IRISUsername]'), "A's trace address needs a sign-in").toBeVisible();
    await trace.close();

    const stateB = await populatedState(rowsB);
    expect(stateB.reminder, "B's reminder is pending").toBe('pending');
    expect(stateB.waiting, 'with its waiter').toBeGreaterThan(0);
    expect(stateB.watches, "B's watch is there").toBe(1);
    expect(stateB.approval, "B's request is pending").toBe('pending');
    expect(stateB.pairing, "B's pairing is linked").toBe(rowsB.session);
    expect(stateB.resumeHash, "B's resume hash is kept").not.toBe('');
    expect(await auditCount(mark, 'Approval', rowsB.approval, 'cancelled//web'), 'no entry names B').toBe(0);

    await signInFromSplash(pageA);
    await expect(mainOf(pageA)).toHaveAttribute('data-snapshot', 'loaded');
    const next = await epochOf(pageA);
    epochs.push(next);
    expect(next, "A's next sign-in gives a new epoch").not.toBe(epochA);
  } finally {
    await signOutGroup(contextA);
    await signOutGroup(contextB);
    for (const rows of populated) await cleanPopulated(rows);
    for (const epoch of epochs) await removeSession(epoch);
    await contextA.close();
    await contextB.close();
  }
});

/** O3: a failed /session/end. */
test('O3: when /session/end fails, the page signs the group out, shows the plain splash and the session stays resumable', async ({ page, context }) => {
  let epoch = '';
  try {
    const log = recordRequests(context);
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    epoch = await epochOf(page);
    await page.route('**/ocutalon/api/v1/session/end', (route) => route.fulfill({ status: 500, json: { error: 'server_error' } }));
    const mark = log.mark();
    await pressSignOut(page);
    await confirmSignOut(page);
    await expect(page.getByRole('button', { name: 'Sign in and start', exact: true }), 'the plain splash shows').toBeVisible({ timeout: 60_000 });
    const landed = new URL(page.url());
    expect(landed.pathname + landed.search, 'at the plain address, not at a sign-out address').toBe('/ocutalon/');
    expect(log.since(mark).some((url) => /\/ocutalon\/\?IRISLogout=end&t=/.test(url)), 'the page sent the group sign-out as a request').toBe(true);
    expect((await context.request.get(STATE)).status(), "the context's CSP session is gone").toBe(401);
    expect(await resumeCookie(context), 'the resume cookie is kept').toBeDefined();
    await page.unroute('**/ocutalon/api/v1/session/end');
    await signInFromSplash(page);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    expect(await epochOf(page), 'and signing in resumes the same epoch').toBe(epoch);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch) await removeSession(epoch);
  }
});
