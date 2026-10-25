import { expect, test, type BrowserContext, type Locator, type Page, type Response } from '@playwright/test';

import { STATE } from '../e2e/support/api';
import { fixtureUser } from '../e2e/support/iris';
import { announcements, recordAnnouncements } from '../e2e/support/page';
import { drawnMessages, postTurn, type Cursor, type Turn } from '../e2e/support/trace';
import { signIn } from '../e2e/sign-in/helpers';
import { signOutGroup } from './support';

/**
 * Story 16.1, the demo account on the page of the online-demo throwaway (O4 to O6; matrix rows 10 to 12). Every case is the DEMOACCOUNT
 * (the unit's test start values), posts the turn it needs through the API of its own page session, and signs out of the whole sign-in
 * group in `finally`.
 * - O4: the turn's Trace link and the Visual Trace menu's "Open my conversation in Visual Trace" each open a new tab at the link's
 *   traceUrl that never shows a sign-in field and draws the turn.
 * - O5: the menu holds the read-only account's credentials from /state, below the conversation link, in the mono type with a named copy
 *   button each; a press puts the exact value on the clipboard, shows "Copied" in its row and announces "Copied" once.
 * - O6: when the clipboard rejects the write, the row shows the failure line, announces it and the page's selection is exactly the row's
 *   value; a later copy that succeeds takes the failure line away.
 * The texts are written out here, as the independent oracle of the page's own.
 */
test.describe.configure({ timeout: 120_000 });

const KIND = 'DEMOACCOUNT';
const TRACE_NAME = 'Trace (opens in a new tab)';
const CONVERSATION_NAME = 'Open my conversation in Visual Trace (opens in a new tab)';
const COPY_USER = 'Copy Visual Trace user name';
const COPY_PASSWORD = 'Copy Visual Trace password';
const COPY_FAILED = "Couldn't copy. Select the text and copy it yourself.";

const mainOf = (page: Page): Locator => page.locator('main.main');
const traceMenu = (page: Page): Locator => page.getByRole('button', { name: 'Visual Trace', exact: true });

/**
 * Signs the demo account in at the page, waits for the loaded snapshot, and returns a cursor at the end of its session stream. The live
 * region's announcements are recorded from the start, for the copy cases.
 */
async function open(page: Page): Promise<Cursor> {
  await recordAnnouncements(page);
  const { user, password } = fixtureUser(KIND);
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  const state = (await (await page.request.get(STATE)).json()) as { streams: { session: number } };
  return { seq: state.streams.session };
}

/** The read-only account that the unit published: the values of its test start values. */
const published = (): { user: string; password: string } => fixtureUser('READONLYACCOUNT');

/** The tab that the action opens, with the answers of every trace document recorded: a sign-in field in any of them is a failure. */
async function opensTabStrict(context: BrowserContext, action: () => Promise<unknown>): Promise<{ popup: Page; signInPages: string[] }> {
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
async function expectOpenedDirectly(opened: { popup: Page; signInPages: string[] }, turn: Turn, label: string): Promise<void> {
  const { popup, signInPages } = opened;
  const want = new URL(turn.traceUrl, 'http://stack.invalid');
  await expect.poll(() => new URL(popup.url()).pathname, { message: `${label}: the tab is at the link's page`, timeout: 30_000 }).toBe(want.pathname);
  expect(new URL(popup.url()).searchParams.get('SESSIONID'), `${label}: and at the link's session`).toBe(want.searchParams.get('SESSIONID'));
  const drawn = await drawnMessages(popup);
  expect(drawn.ids, `${label}: Visual Trace draws the turn`).toContain(String(turn.traceHeaderId));
  await expect(popup.locator('input[name=IRISPassword]'), `${label}: no sign-in field`).toHaveCount(0);
  expect(signInPages, `${label}: no document of the tab was a sign-in page`).toEqual([]);
}

/** O4: a trace link and "Open my conversation in Visual Trace" open Visual Trace with no second sign-in. */
test('O4: the demo account presses a trace link and Open my conversation, and Visual Trace opens signed in', async ({ page, context }) => {
  try {
    const cursor = await open(page);
    const turn = await postTurn(page.request, cursor, 1, 'online-demo');
    const link = page.locator(`app-chat-panel [data-part="reply"][data-key="${turn.clientId}"] app-decision-strip app-trace-link a`);
    await expect(link, 'the turn has its Trace link').toHaveCount(1, { timeout: 30_000 });
    await expect(link).toHaveAccessibleName(TRACE_NAME);
    const fromLink = await opensTabStrict(context, () => link.click());
    await expectOpenedDirectly(fromLink, turn, 'the Trace link');
    await fromLink.popup.close();

    await traceMenu(page).click();
    const menu = page.getByRole('dialog', { name: 'Visual Trace', exact: true });
    await expect(menu, 'the online demo shows no sign-in help').toBeVisible();
    const conversation = menu.getByRole('link', { name: CONVERSATION_NAME, exact: true });
    await expect(conversation).toHaveAttribute('href', turn.traceUrl);
    const fromMenu = await opensTabStrict(context, () => conversation.click());
    await expectOpenedDirectly(fromMenu, turn, 'the conversation link');
    await fromMenu.popup.close();
  } finally {
    await signOutGroup(page);
  }
});

/** O5: the menu's credential rows hold the read-only account, and each copy button puts its value on the clipboard. */
test('O5: the Visual Trace menu shows the read-only credentials with working copy buttons', async ({ page, context }) => {
  try {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    const cursor = await open(page);
    await postTurn(page.request, cursor, 2, 'online-demo');
    const account = published();
    const snapshot = (await (await page.request.get(STATE)).json()) as Record<string, unknown>;
    expect(snapshot['traceAccount'], '/state carries the read-only account').toEqual({ user: account.user, password: account.password });
    expect(Object.keys(snapshot).at(-1), 'as its last key').toBe('traceAccount');

    await traceMenu(page).click();
    const menu = page.getByRole('dialog', { name: 'Visual Trace', exact: true });
    await expect(menu).toBeVisible();
    const rows = menu.locator('app-credential-rows .row');
    await expect(rows, 'two credential rows').toHaveCount(2);
    await expect(rows.nth(0).locator('.label')).toHaveText('User name');
    await expect(rows.nth(1).locator('.label')).toHaveText('Password');
    const conversation = menu.getByRole('link', { name: CONVERSATION_NAME, exact: true });
    const linkBox = (await conversation.boundingBox())!;
    expect((await rows.nth(0).boundingBox())!.y, 'the rows are below the conversation link').toBeGreaterThan(linkBox.y + linkBox.height - 1);
    await expect(conversation, 'the link stays the first focus').toBeFocused();

    const pairs = [
      { row: rows.nth(0), key: 'user', value: account.user, button: COPY_USER },
      { row: rows.nth(1), key: 'password', value: account.password, button: COPY_PASSWORD },
    ];
    for (const { row, key, value, button } of pairs) {
      const text = row.locator(`[data-credential="${key}"]`);
      await expect(text).toHaveText(value);
      expect(await text.evaluate((node) => getComputedStyle(node).fontFamily), `${key}: the value is in the mono type`).toContain('JetBrains Mono');
      const heard = await announcements(page, 'Copied');
      await menu.getByRole('button', { name: button, exact: true }).click();
      await expect(row.getByText('Copied', { exact: true }), `${key}: the row says Copied`).toBeVisible();
      await expect.poll(() => announcements(page, 'Copied'), { message: `${key}: Copied is announced once`, timeout: 5000 }).toBe(heard + 1);
      expect(await page.evaluate(() => navigator.clipboard.readText()), `${key}: the clipboard holds the exact value`).toBe(value);
    }
    await expect(menu.getByText('Copied', { exact: true }), 'Copied goes after 2 seconds').toHaveCount(0, { timeout: 5000 });
  } finally {
    await signOutGroup(page);
  }
});

/** O6: a clipboard that rejects the write gives the failure line and selects the row's value. */
test('O6: a copy that fails shows the failure line and selects the value', async ({ page }) => {
  try {
    await page.addInitScript(() => {
      Object.defineProperty(navigator.clipboard, 'writeText', { configurable: true, value: () => Promise.reject(new Error('denied')) });
    });
    const cursor = await open(page);
    await postTurn(page.request, cursor, 3, 'online-demo');
    const account = published();
    await traceMenu(page).click();
    const menu = page.getByRole('dialog', { name: 'Visual Trace', exact: true });
    await expect(menu).toBeVisible();
    const selection = (): Promise<string> => page.evaluate(() => window.getSelection()?.toString() ?? '');

    await menu.getByRole('button', { name: COPY_PASSWORD, exact: true }).click();
    await expect(menu.getByText(COPY_FAILED, { exact: true }), 'the failure line shows').toBeVisible();
    await expect(menu.getByText('Copied', { exact: true })).toHaveCount(0);
    expect(await selection(), 'the selection is exactly the password').toBe(account.password);
    await expect.poll(() => announcements(page, COPY_FAILED), { message: 'the failure is announced', timeout: 5000 }).toBe(1);

    await menu.getByRole('button', { name: COPY_USER, exact: true }).click();
    await expect(menu.getByText(COPY_FAILED, { exact: true }), 'the line stays').toBeVisible();
    expect(await selection(), 'and now the selection is exactly the user name').toBe(account.user);
    await expect.poll(() => announcements(page, COPY_FAILED), { message: 'each failure is announced', timeout: 5000 }).toBe(2);

    await page.evaluate(() => {
      Object.defineProperty(navigator.clipboard, 'writeText', { configurable: true, value: () => Promise.resolve() });
    });
    await menu.getByRole('button', { name: COPY_USER, exact: true }).click();
    await expect(menu.getByText('Copied', { exact: true }), 'a copy that succeeds says Copied').toBeVisible();
    await expect(menu.getByText(COPY_FAILED, { exact: true }), 'and takes the failure line away').toHaveCount(0);
  } finally {
    await signOutGroup(page);
  }
});
