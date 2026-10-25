import { expect, test, type Page, type PlaywrightWorkerArgs } from '@playwright/test';

import { STATE } from '../e2e/support/api';
import { chk, fixtureUser, irisScript } from '../e2e/support/iris';
import { drawnMessages, postTurn, signInToTrace, type Cursor, type Turn } from '../e2e/support/trace';
import { signInOverHttp } from '../e2e/sign-in/helpers';
import { SIGN_OUT, signInFromSplash, signOutGroup } from './support';

/**
 * Story 16.1, the read-only public account in a real browser on the online-demo throwaway (O1 to O3; matrix rows 7 to 9). Every case
 * is the READONLYACCOUNT (the unit's test start values) and signs out of the whole sign-in group in `finally`.
 * - O1: signed in through the form at /ocutalon, the account sees the no-role message, never the shell, and holds no session.
 * - O2: signed in at one trace application, it opens Visual Trace and the message viewer in OCUTALON and in OCUORDERS on the sessions
 *   that the case seeds itself (a turn of the demo account through the API, one order of the Orders partner), with one sign-in.
 * - O3: it is refused the production, resend, SQL, security, settings and credential pages in both applications, and Visual Trace's
 *   canResend is false.
 * The texts are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 120_000 });

const NO_ROLE = "This IRIS account doesn't have the OcuTalon user role. Ask an OcuTalon admin to add it.";
const KIND = 'READONLYACCOUNT';
const TRACES = ['ocutalon', 'ocuorders'] as const;

/** The pages that the read-only account may not open: the portal's production, resend, SQL, security, settings and credential pages. */
const REFUSED = [
  'EnsPortal.ProductionConfig.zen',
  'EnsPortal.Productions.zen',
  'EnsPortal.StartStopFrame.zen',
  'EnsPortal.MessageResend.zen',
  '%25CSP.UI.Portal.SQL.Home.zen',
  'EnsPortal.Credentials.zen',
  '%25CSP.UI.Portal.Users.zen',
  'EnsPortal.DefaultSettings.zen',
] as const;

const tracePage = (namespace: string, page: string): string => `/ocutalon/trace/${namespace}/${page}`;

/** Seeds one OCUTALON turn through the demo account's API, signed in over HTTP and signed out again. */
async function seedTurn(playwright: PlaywrightWorkerArgs['playwright']): Promise<Turn> {
  const api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
  try {
    const { user, password } = fixtureUser('DEMOACCOUNT');
    const answer = await signInOverHttp(api, user, password);
    expect(answer.status(), 'the demo account signs in over HTTP').toBe(200);
    const state = (await (await api.get(STATE)).json()) as { streams: { session: number } };
    const cursor: Cursor = { seq: state.streams.session };
    return await postTurn(api, cursor, 1, 'online-readonly');
  } finally {
    await api.get(SIGN_OUT).catch(() => undefined);
    await api.dispose();
  }
}

/** Seeds one order in OCUORDERS through the Orders production's own entry, and returns the header id of its first message. */
async function seedOrder(): Promise<number> {
  const lines = await irisScript(
    [
      'Set $Namespace="OCUORDERS"',
      'Set before=+$Order(^Ens.MessageHeaderD(""),-1)',
      'Set sc=##class(OcuTalon.Demo.Orders.Partner).Send(1,"YYYY-MM-DD")',
      'Write !,"CHK|sc|",$Select($SYSTEM.Status.IsOK(sc):"ok",1:$SYSTEM.Status.GetErrorText(sc))',
      'Write !,"CHK|id|",$Order(^Ens.MessageHeaderD(before))',
    ].join('\n'),
  );
  expect(chk(lines, 'sc'), `the partner's batch is sent (${lines.join(' ')})`).toBe('ok');
  const id = Number(chk(lines, 'id'));
  expect(Number.isInteger(id) && id > 0, `the order has a message header (${lines.join(' ')})`).toBe(true);
  return id;
}

/** Opens a trace application's page as the read-only account: the sign-in form of the application first, when it is shown. */
async function openAsReadOnly(page: Page, path: string): Promise<void> {
  await page.goto(path);
  await signInToTrace(page, KIND);
}

/** Runs the message viewer's own search and waits for at least one row of its table. */
async function expectViewerRows(page: Page, label: string): Promise<void> {
  await expect(page, `${label}: the message viewer`).toHaveTitle(/Message Viewer/, { timeout: 30_000 });
  await page.waitForFunction(() => typeof (window as unknown as { zenPage?: { doSearch?: unknown } }).zenPage?.doSearch === 'function');
  await page.evaluate(() => (window as unknown as { zenPage: { doSearch: () => void } }).zenPage.doSearch());
  await expect(page.locator('table.tpTable tr.tpOdd, table.tpTable tr.tpEven').first(), `${label}: the viewer lists at least one row`).toBeVisible({ timeout: 30_000 });
}

/** O1: the read-only account at /ocutalon sees the no-role message, never the shell, and holds no session. */
test('O1: the read-only account at /ocutalon gets the no-role message and no session', async ({ page }) => {
  const { user, password } = fixtureUser(KIND);
  try {
    await signInFromSplash(page, user, password);
    await expect(page.locator('#ocu-error')).toHaveText(NO_ROLE);
    await expect(page.locator('app-root'), 'the shell is never served').toHaveCount(0);
    expect((await page.request.get(STATE)).status(), 'the session ended').toBe(401);
  } finally {
    await signOutGroup(page);
  }
});

/** O2: the read-only account opens Visual Trace and the message viewer in both namespaces with one sign-in. */
test('O2: the read-only account opens Visual Trace and the message viewer in OCUTALON and OCUORDERS with one sign-in', async ({ page, playwright }) => {
  const turn = await seedTurn(playwright);
  const order = await seedOrder();
  try {
    await openAsReadOnly(page, turn.traceUrl);
    const drawn = await drawnMessages(page);
    expect(drawn.ids, 'OCUTALON: Visual Trace draws the turn').toContain(String(turn.traceHeaderId));
    await page.goto(tracePage('ocutalon', 'EnsPortal.MessageViewer.zen'));
    await expectViewerRows(page, 'OCUTALON');

    await page.goto(tracePage('ocuorders', `EnsPortal.VisualTrace.zen?SESSIONID=${order}`));
    await expect(page.locator('input[name=IRISPassword]'), 'the second application asks for no sign-in').toHaveCount(0);
    const orders = await drawnMessages(page);
    expect(orders.ids, 'OCUORDERS: Visual Trace draws the order').toContain(String(order));
    await page.goto(tracePage('ocuorders', 'EnsPortal.MessageViewer.zen'));
    await expect(page.locator('input[name=IRISPassword]'), 'nor does its message viewer').toHaveCount(0);
    await expectViewerRows(page, 'OCUORDERS');
  } finally {
    await signOutGroup(page);
  }
});

/** O3: the read-only account is refused every page outside the trace application's seven classes, and cannot resend. */
test('O3: the read-only account is refused the production, resend, SQL, security, settings and credential pages', async ({ page }) => {
  try {
    await openAsReadOnly(page, tracePage('ocutalon', 'EnsPortal.MessageViewer.zen'));
    await expect(page).toHaveTitle(/Message Viewer/, { timeout: 30_000 });
    for (const namespace of TRACES) {
      for (const name of REFUSED) {
        const answer = await page.request.get(tracePage(namespace, name));
        expect(answer.status(), `${namespace}: ${name} answers 404`).toBe(404);
      }
    }
    for (const namespace of TRACES) {
      await page.goto(tracePage(namespace, 'EnsPortal.VisualTrace.zen?SESSIONID=1'));
      await page.waitForFunction(() => (window as unknown as { zenPage?: unknown }).zenPage !== undefined);
      const canResend = await page.evaluate(() => (window as unknown as { zenPage: { canResend: unknown } }).zenPage.canResend);
      expect(canResend, `${namespace}: canResend is false`).toBe(false);
    }
  } finally {
    await signOutGroup(page);
  }
});
