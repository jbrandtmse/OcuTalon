import { expect, test, type Locator, type Page } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { loadedAfter } from '../support/floor';
import { NAV_LINKS_USER } from '../support/header-nav';
import { localDate, seedHistoryDecisions, type HistoryDecisionSeed } from '../support/history';
import { cleanFixtureRows, fixtureUser, seedIncident } from '../support/iris';
import { sessionRefOfUser } from '../support/memory';
import { freeze } from '../support/clock';
import { announcements, recordAnnouncements } from '../support/page';
import { helpSeen, stubTraces } from '../support/trace';

/**
 * Story 25.2, the History page (H1 to H15), in a real browser against a real stack, signed in as the LIVE fixture user (OcuTalonUser only, the online demo visitors'
 * role). The cases read rows that this file seeds once, on local days that no other case uses (45 to 47 days ago, so an address names its day), through the
 * product's test fixture, with a second session's (PANEL) rows beside them that must never show:
 *
 *   row  day  outcome  channel   fallback  reasons / notes
 *   U1   45   ignore   web       no        "Noise."  confidence 0.9, cost 0.001
 *   U2   45   digest   mailbox   no
 *   U3   45   tellnow  phone     no
 *   U4   45   act      mailbox   no        "Needs a reply." and "Second line."
 *   U5   45   digest   (none)    yes       a fallback no model call served: it has no channel
 *   P01..P26  46  act  slack     no        26 rows, the second page holds P01
 *
 * and two incidents (noticed in 2031, so they head the list): one closed with a stored summary, a count of 4 and a diagnosis trace, one open with no summary.
 * The texts are written out here, as the independent oracle of the page's own. H9, H12 and H15 stub the history routes in the browser to fail a read.
 */
const TITLE = 'History \u00B7 OcuTalon';
const SIGN_IN_NAME = 'Open in Visual Trace (shows sign-in help first)';
const PLAIN_NAME = 'Trace (opens in a new tab)';
const DECISIONS = '**/ocutalon/api/v1/history/decisions*';
const INCIDENTS = '**/ocutalon/api/v1/history/incidents*';
const ERROR = "Couldn't load your history.";
const CHANNEL_WORDS = /Unknown|Web chat|Simulated|Telegram|Email|Webhook|Slack|System|Heartbeat/;
const stamp = Date.now().toString(36);
const tag = `zz-hist-${stamp}`;
const live = (): { user: string; password: string } => fixtureUser('LIVE');
const panel = (): { user: string; password: string } => fixtureUser('PANEL');

let d45 = '';
let d46 = '';
const made: string[] = [];

test.beforeAll(async () => {
  test.setTimeout(180_000);
  d45 = await localDate(45);
  d46 = await localDate(46);
  const session = await sessionRefOfUser(live().user);
  const at = (time: string): Pick<HistoryDecisionSeed, 'daysAgo' | 'time'> => ({ daysAgo: 45, time });
  const own = await seedHistoryDecisions({ sessionRef: session }, [
    { ...at('09:00:00'), outcome: 'ignore', summary: `${tag} U1`, channel: 'web', reasons: 'Noise.', confidence: 0.9, costUSD: 0.001 },
    { ...at('10:00:00'), outcome: 'digest', summary: `${tag} U2`, channel: 'mailbox', reasons: 'Saved for the digest.' },
    { ...at('11:00:00'), outcome: 'tellnow', summary: `${tag} U3`, channel: 'phone', reasons: 'Needs you now.' },
    { ...at('12:00:00'), outcome: 'act', summary: `${tag} U4`, channel: 'mailbox', reasons: 'Needs a reply.\nSecond line.' },
    { ...at('13:00:00'), outcome: 'digest', summary: `${tag} U5`, fallback: true, fallbackReason: 'no_key', reasons: 'Fixed rules decided.' },
  ]);
  const many = await seedHistoryDecisions(
    { sessionRef: session },
    Array.from({ length: 26 }, (_one, index) => ({ outcome: 'act', summary: `${tag} P${String(index + 1).padStart(2, '0')}`, channel: 'slack', daysAgo: 46, time: `08:${String(index).padStart(2, '0')}:00` })),
  );
  const theirs = await seedHistoryDecisions({ sessionRef: await sessionRefOfUser(panel().user) }, [
    { outcome: 'act', summary: `${tag} THEIRS`, channel: 'web', daysAgo: 45, time: '14:00:00' },
    { outcome: 'act', summary: `${tag} THEIRS-P`, channel: 'slack', daysAgo: 46, time: '09:30:00' },
  ]);
  made.push(...own.map((one) => one.ref), ...many.map((one) => one.ref), ...theirs.map((one) => one.ref));
  const summary = JSON.stringify({ parts: [{ key: 'summary.noFixRan', slots: {} }], lines: [] });
  made.push(
    await seedIncident({ sessionRef: session }, {
      state: 'closed', summary, traceHeaderId: 77, count: 4, itemNoun: { one: 'order', other: 'orders' }, firstAt: '2031-02-01T09:00:00Z', noticedAt: '2031-02-01T09:30:00Z', closedAt: '2031-02-01T11:00:00Z',
    }),
    await seedIncident({ sessionRef: session }, { state: 'open', count: 1, firstAt: '2031-02-02T09:00:00Z', noticedAt: '2031-02-02T09:30:00Z' }),
    await seedIncident({ sessionRef: await sessionRefOfUser(panel().user) }, { state: 'open', count: 99, noticedAt: '2031-02-03T09:30:00Z' }),
  );
});

test.afterAll(async () => {
  await cleanFixtureRows(made);
});

const nav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const tabOf = (page: Page, name: 'Decisions' | 'Incidents'): Locator => page.getByRole('tab', { name, exact: true });
const rowsOf = (page: Page): Locator => page.locator('[data-part="history-decisions"] > li');
const incidentsOf = (page: Page): Locator => page.locator('[data-part="history-incidents"] > li');
const control = (page: Page, label: string): Locator => page.getByLabel(label, { exact: true });
/** The failed read's own region, on either tab: the live region holds the same words, so a page-wide text search would count that too. */
const failedOf = (page: Page): Locator => page.locator('[data-part="history-failed"]');
const pager = (page: Page, name: string): Locator => page.getByRole('navigation', { name, exact: true });
const hashOf = (page: Page): string => new URL(page.url()).hash;
const rowWith = (page: Page, text: string): Locator => rowsOf(page).filter({ hasText: text });

/** Signs the LIVE user in (the sign-in help seen when seen is set, and the trace tabs stubbed) and loads the page. */
async function openApp(page: Page, seen = true): Promise<void> {
  await stubTraces(page.context());
  if (seen) await helpSeen(page);
  await loadedAfter(page, () => signIn(page, live().user, live().password));
}

/**
 * After a successful Retry the announcement of the failure is withdrawn: the polite live region, which takes a text 100 ms after it is handed one, holds no
 * trace of it once that time has passed.
 */
async function expectNoStaleError(page: Page): Promise<void> {
  await page.waitForTimeout(300);
  await expect(page.locator('.cdk-live-announcer-element'), 'the failure is no longer announced').not.toContainText(ERROR);
}

/** Goes to the History page at the address (the part after #/history) by the page's own address, without a reload. */
async function visit(page: Page, query: string): Promise<void> {
  await page.evaluate((hash) => {
    window.location.hash = hash;
  }, `#/history${query}`);
  await expect(tabOf(page, 'Decisions')).toBeVisible();
}

/** The parts of a decision row's meta line that are text (not the separators). */
async function metaOf(row: Locator): Promise<string[]> {
  return (await row.locator('.meta > span:not([aria-hidden])').allInnerTexts()).map((text) => text.trim());
}

test('H1: History is in the header between Documents and Usage, opens #/history titled History, and is the current page', async ({ page }) => {
  await openApp(page);
  const links = nav(page).getByRole('link');
  await expect(links).toHaveText(NAV_LINKS_USER);
  await links.filter({ hasText: 'History' }).click();
  await expect(page).toHaveTitle(TITLE);
  expect(hashOf(page)).toBe('#/history');
  await expect(nav(page).getByRole('link', { name: 'History', exact: true })).toHaveAttribute('aria-current', 'page');
  await expect(nav(page).getByRole('link', { name: 'Usage', exact: true })).not.toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('heading', { level: 1, name: 'History' })).toHaveCount(1);
  await expect(page.getByRole('tablist')).toHaveAccessibleName('History');
  await expect(tabOf(page, 'Decisions')).toHaveAttribute('aria-selected', 'true');
  await expect(tabOf(page, 'Incidents')).toHaveAttribute('aria-selected', 'false');
  await expect(page.getByRole('heading', { level: 2, name: 'Decisions' })).toHaveCount(1);
  await expect(page.getByRole('heading', { level: 2, name: 'Incidents' })).toHaveCount(0);
});

test('H2: every filter changes the address, the list follows, and a reload and a copied link keep it', async ({ page, context }) => {
  await openApp(page);
  await visit(page, `?day=${d45}`);
  await expect(rowsOf(page)).toHaveCount(5);
  await expect(rowsOf(page).first()).toContainText(`${tag} U5`);
  await expect(page.getByText(`${tag} THEIRS`)).toHaveCount(0);

  await control(page, 'Outcome').selectOption({ label: 'Tell now' });
  await expect(page).toHaveURL(/outcome=tellnow/);
  await expect(rowsOf(page)).toHaveCount(2);
  await expect(rowsOf(page).nth(0)).toContainText(`${tag} U5`);
  await expect(rowsOf(page).nth(1)).toContainText(`${tag} U3`);
  await control(page, 'Outcome').selectOption({ label: 'Digest' });
  await expect(rowsOf(page)).toHaveCount(1);
  await expect(rowsOf(page).first()).toContainText(`${tag} U2`);
  await control(page, 'Outcome').selectOption({ label: 'Any outcome' });
  await expect(page).not.toHaveURL(/outcome=/);

  await control(page, 'Fallback').selectOption({ label: 'Fallback only' });
  await expect(page).toHaveURL(/fallback=yes/);
  await expect(rowsOf(page)).toHaveCount(1);
  await control(page, 'Fallback').selectOption({ label: 'Without fallback' });
  await expect(rowsOf(page)).toHaveCount(4);
  await control(page, 'Fallback').selectOption({ label: 'All decisions' });

  await control(page, 'Channel').selectOption({ label: 'Simulated mailbox' });
  await expect(page).toHaveURL(/channel=mailbox/);
  await expect(rowsOf(page)).toHaveCount(2);
  await control(page, 'Outcome').selectOption({ label: 'Act' });
  await expect(rowsOf(page)).toHaveCount(1);
  await expect(rowsOf(page).first()).toContainText(`${tag} U4`);
  const address = page.url();
  expect(hashOf(page)).toContain('outcome=act');
  expect(hashOf(page)).toContain('channel=mailbox');
  expect(hashOf(page)).toContain(`day=${d45}`);

  await page.reload();
  await expect(control(page, 'Outcome')).toHaveValue('act');
  await expect(control(page, 'Channel')).toHaveValue('mailbox');
  await expect(control(page, 'Date')).toHaveValue(d45);
  await expect(rowsOf(page)).toHaveCount(1);
  const copy = await context.newPage();
  await copy.goto(address);
  await expect(control(copy, 'Outcome')).toHaveValue('act');
  await expect(control(copy, 'Channel')).toHaveValue('mailbox');
  await expect(rowsOf(copy)).toHaveCount(1);
  await expect(rowsOf(copy).first()).toContainText(`${tag} U4`);
  await copy.close();

  await control(page, 'Date').fill('');
  await expect(page, 'an emptied date input clears the day').not.toHaveURL(/day=/);
  await expect(page).toHaveURL(/outcome=act/);
  await control(page, 'Date').fill(d46);
  await expect(page).toHaveURL(new RegExp(`day=${d46}`));
  await expect(page.getByText('No decisions match these filters.', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Clear filters', exact: true }).click();
  await expect(page).not.toHaveURL(/outcome=|channel=|day=/);
  await expect(control(page, 'Outcome')).toHaveValue('');
  await expect(page.getByRole('button', { name: 'Clear filters', exact: true })).toHaveCount(0);
  await expect(control(page, 'Outcome')).toBeFocused();
});

test('H3: 26 decisions page 25 and 1, with Previous and Next, a page past the last is replaced by the last, and Back works', async ({ page }) => {
  await openApp(page);
  await visit(page, `?day=${d46}&channel=slack`);
  await expect(rowsOf(page)).toHaveCount(25);
  await expect(rowsOf(page).first()).toContainText(`${tag} P26`);
  await expect(page.getByText('Page 1 of 2', { exact: true })).toBeVisible();
  await expect(pager(page, 'Decision pages')).toBeVisible();
  const previous = page.getByRole('button', { name: 'Previous page', exact: true });
  const next = page.getByRole('button', { name: 'Next page', exact: true });
  await expect(previous).toHaveAttribute('aria-disabled', 'true');
  await expect(next).not.toHaveAttribute('aria-disabled', 'true');
  await next.click();
  await expect(page).toHaveURL(/page=2/);
  await expect(page.getByText('Page 2 of 2', { exact: true })).toBeVisible();
  await expect(rowsOf(page)).toHaveCount(1);
  await expect(rowsOf(page).first()).toContainText(`${tag} P01`);
  await expect(page.locator('main.history'), 'a page turn keeps keyboard focus on the page').toBeFocused();
  await expect(next).toHaveAttribute('aria-disabled', 'true');
  await page.reload();
  await expect(page.getByText('Page 2 of 2', { exact: true })).toBeVisible();
  await previous.click();
  await expect(page).not.toHaveURL(/page=/);
  await expect(rowsOf(page)).toHaveCount(25);
  await page.goBack();
  await expect(page).toHaveURL(/page=2/);
  await expect(rowsOf(page)).toHaveCount(1);

  await visit(page, `?day=${d45}`);
  await expect(rowsOf(page)).toHaveCount(5);
  await visit(page, `?day=${d46}&channel=slack&page=9999`);
  await expect(page).toHaveURL(/page=2(?:&|$)/);
  await expect(page).not.toHaveURL(/page=9999/);
  await expect(rowsOf(page)).toHaveCount(1);
  await expect(page.getByText('Page 2 of 2', { exact: true })).toBeVisible();
  await page.goBack();
  await expect(page, 'the last page replaced the stale address, so Back goes to the address before it').toHaveURL(new RegExp(`day=${d45}$`));
  await expect(rowsOf(page)).toHaveCount(5);
  await visit(page, `?day=${d46}&channel=slack&outcome=foo&page=01`);
  await expect(page).not.toHaveURL(/outcome=foo|page=01/);
  await expect(rowsOf(page)).toHaveCount(25);
  await expect(pager(page, 'Decision pages')).toBeVisible();
  await page.goBack();
  await expect(page, 'the cleaned address replaced the hand-edited one too').toHaveURL(new RegExp(`day=${d45}$`));
  await expect(rowsOf(page)).toHaveCount(5);
  await expect(pager(page, 'Decision pages')).toHaveCount(0);

  await visit(page, `?day=${d46}&channel=slack&page=2`);
  await expect(rowsOf(page)).toHaveCount(1);
  await control(page, 'Outcome').selectOption({ label: 'Act' });
  await expect(page).toHaveURL(/outcome=act/);
  await expect(page, 'a filter change goes back to page 1').not.toHaveURL(/page=/);
  await expect(rowsOf(page)).toHaveCount(25);
  await expect(rowsOf(page).first()).toContainText(`${tag} P26`);
  await visit(page, `?day=${d46}&channel=slack&page=2`);
  await expect(rowsOf(page)).toHaveCount(1);
  await tabOf(page, 'Incidents').click();
  await expect(page).toHaveURL(/tab=incidents/);
  await expect(page, 'a tab change goes back to page 1').not.toHaveURL(/page=/);
});

test('H4: a decision row expands its reasons in place, with its trace link beside the button that opens a new tab', async ({ page, context }) => {
  await openApp(page);
  await visit(page, `?day=${d45}`);
  const row = rowWith(page, `${tag} U4`);
  const button = row.getByRole('button');
  await expect(button).toHaveAttribute('aria-expanded', 'false');
  await expect(row).toContainText('Needs a reply.');
  await expect(row).not.toContainText('Second line.');
  await expect(row.locator('.chip, app-outcome-chip').first()).toContainText('Act');
  await button.click();
  await expect(button).toHaveAttribute('aria-expanded', 'true');
  await expect(row).toContainText('Second line.');
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await button.click();
  await expect(button).toHaveAttribute('aria-expanded', 'false');
  await expect(row).not.toContainText('Second line.');

  const link = row.locator('app-trace-link a');
  await expect(link).toHaveCount(1);
  await expect(row.locator('button app-trace-link')).toHaveCount(0);
  await expect(link).toHaveAttribute('target', '_blank');
  await expect(link).toHaveAccessibleName(PLAIN_NAME);
  await expect(link).toHaveAttribute('href', /SESSIONID=42/);
  const [popup] = await Promise.all([context.waitForEvent('page'), link.click()]);
  await popup.waitForLoadState('domcontentloaded');
  expect(popup.url()).toContain('SESSIONID=42');
  await popup.close();
  const fallbackRow = rowWith(page, `${tag} U5`);
  await expect(fallbackRow.locator('.chip, app-outcome-chip').first()).toContainText('Tell now');
  await expect(fallbackRow).toContainText('Fallback');
});

test('H5: before the sign-in help is seen the trace link says so and opens the help, not a tab', async ({ page }) => {
  await openApp(page, false);
  await visit(page, `?day=${d45}`);
  const link = rowWith(page, `${tag} U1`).locator('app-trace-link a');
  await expect(link).toHaveAccessibleName(SIGN_IN_NAME);
  await expect(link).toHaveAttribute('aria-haspopup', 'dialog');
});

test('H6: a decision with no usage row shows no channel text at all, and one with a channel shows it after the time', async ({ page }) => {
  await openApp(page);
  await visit(page, `?day=${d45}`);
  await expect(rowsOf(page)).toHaveCount(5);
  const bare = await metaOf(rowWith(page, `${tag} U5`));
  expect(bare.join(' | '), 'no channel word, no Unknown and no label').not.toMatch(CHANNEL_WORDS);
  expect(bare, 'only the time').toHaveLength(1);
  await expect(rowWith(page, `${tag} U5`)).not.toContainText(CHANNEL_WORDS);
  const first = await metaOf(rowWith(page, `${tag} U1`));
  expect(first.length, 'time, channel, confidence and cost').toBe(4);
  expect(first[1]).toBe('Web chat');
  expect(first[2]).toBe('Confidence 0.90');
  const phone = await metaOf(rowWith(page, `${tag} U3`));
  expect(phone[1]).toBe('Simulated phone');
});

test('H7: the tabs use aria-selected and keys, switch only when pressed, and the Incidents tab lists the incidents with their summary and trace link', async ({ page }) => {
  await openApp(page);
  await visit(page, `?day=${d45}`);
  await expect(rowsOf(page)).toHaveCount(5);
  await page.waitForTimeout(1500);
  await expect(tabOf(page, 'Decisions')).toHaveAttribute('aria-selected', 'true');
  await expect(tabOf(page, 'Decisions')).toHaveAttribute('tabindex', '0');
  await expect(tabOf(page, 'Incidents')).toHaveAttribute('tabindex', '-1');

  await tabOf(page, 'Decisions').focus();
  await page.keyboard.press('ArrowRight');
  await expect(tabOf(page, 'Incidents')).toHaveAttribute('aria-selected', 'true');
  await expect(tabOf(page, 'Incidents')).toBeFocused();
  await expect(page).toHaveURL(/tab=incidents/);
  await expect(page.getByRole('tabpanel', { name: 'Incidents' })).toBeVisible();
  await expect(page.getByRole('tabpanel', { name: 'Decisions' })).toHaveCount(0);
  await expect(incidentsOf(page).first()).toBeVisible();

  const closed = incidentsOf(page).filter({ hasText: 'No fix ran, so nothing was changed.' });
  await expect(closed).toHaveCount(1);
  await expect(closed.locator('app-incident-state-chip')).toHaveText('Closed');
  await expect(closed.locator('.headline')).toHaveText(/^4 orders failed since /);
  await expect(closed.locator('.meta')).toContainText('Noticed ');
  await expect(closed.locator('.meta')).toContainText('Closed ');
  await expect(closed.locator('app-trace-link a')).toHaveAccessibleName(PLAIN_NAME);
  await expect(closed.locator('app-trace-link a')).toHaveAttribute('href', /SESSIONID=77/);
  const open = incidentsOf(page).filter({ hasText: 'No summary yet. OcuTalon writes one when the incident closes.' });
  await expect(open).toHaveCount(1);
  await expect(open.locator('app-incident-state-chip')).toHaveText('Open');
  await expect(open.locator('.headline')).toHaveText(/^1 message failed since /);
  await expect(open.locator('.meta')).toContainText('Noticed ');
  await expect(open.locator('.meta')).not.toContainText('Closed ');
  await expect(open.locator('app-trace-link')).toHaveCount(0);
  await expect(page.getByText('99 messages')).toHaveCount(0);
  for (const row of await incidentsOf(page).all()) expect((await row.boundingBox())!.height).toBeGreaterThanOrEqual(40);

  await page.keyboard.press('ArrowLeft');
  await expect(tabOf(page, 'Decisions')).toHaveAttribute('aria-selected', 'true');
  await expect(rowsOf(page)).toHaveCount(5);
  await tabOf(page, 'Incidents').focus();
  await page.keyboard.press('Space');
  await expect(tabOf(page, 'Incidents')).toHaveAttribute('aria-selected', 'true');
  await tabOf(page, 'Decisions').focus();
  await page.keyboard.press('Enter');
  await expect(tabOf(page, 'Decisions')).toHaveAttribute('aria-selected', 'true');
  await page.reload();
  await expect(tabOf(page, 'Decisions')).toHaveAttribute('aria-selected', 'true');
});

test('H8: every decision row is at least 40px tall with its outcome chip first', async ({ page }) => {
  await openApp(page);
  await visit(page, `?day=${d45}`);
  await expect(rowsOf(page)).toHaveCount(5);
  for (const row of await rowsOf(page).all()) {
    expect((await row.boundingBox())!.height).toBeGreaterThanOrEqual(40);
    const first = await row.getByRole('button').evaluate((button) => (button.firstElementChild?.tagName ?? '').toLowerCase());
    expect(first, 'the chip is the first thing in the row').toBe('app-outcome-chip');
  }
});

test('H9: the empty texts, and a failed read says so with Retry', async ({ page }) => {
  await openApp(page);
  await page.route(DECISIONS, (route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ page: 1, pages: 1, decisions: [] }) }));
  await page.route(INCIDENTS, (route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ page: 1, pages: 1, incidents: [] }) }));
  await visit(page, '');
  await expect(page.getByText('No decisions yet.', { exact: true })).toBeVisible();
  await visit(page, '?outcome=act');
  await expect(page.getByText('No decisions match these filters.', { exact: true })).toBeVisible();
  await visit(page, '?tab=incidents');
  await expect(page.getByText('No incidents yet.', { exact: true })).toBeVisible();
  await page.unroute(DECISIONS);
  await page.route(DECISIONS, (route) => route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) }));
  await visit(page, `?day=${d45}`);
  await expect(failedOf(page)).toContainText(ERROR);
  await page.unroute(DECISIONS);
  await page.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(rowsOf(page)).toHaveCount(5);
  await expect(failedOf(page), 'the error and Retry are gone with the answer').toHaveCount(0);
  await expectNoStaleError(page);
});

test('H10: another session\'s rows never appear, on either tab', async ({ page }) => {
  await openApp(page);
  await visit(page, `?day=${d45}`);
  await expect(rowsOf(page)).toHaveCount(5);
  await expect(page.locator('main')).not.toContainText(`${tag} THEIRS`);
  await visit(page, `?day=${d46}&channel=slack`);
  await expect(rowsOf(page)).toHaveCount(25);
  await expect(page.locator('main')).not.toContainText('THEIRS-P');
  await visit(page, '?tab=incidents');
  await expect(incidentsOf(page).first()).toBeVisible();
  await expect(page.locator('main')).not.toContainText('99 messages');
});

test('H11: the page works by keyboard alone: the link, a filter, a row and Clear filters', async ({ page }) => {
  await openApp(page);
  await nav(page).getByRole('link', { name: 'History', exact: true }).focus();
  await page.keyboard.press('Enter');
  await expect(tabOf(page, 'Decisions')).toBeVisible();
  await visit(page, `?day=${d45}`);
  await expect(rowsOf(page)).toHaveCount(5);
  await control(page, 'Outcome').focus();
  await expect(control(page, 'Outcome'), 'the filter is a labelled native select that takes focus').toBeFocused();
  await control(page, 'Outcome').selectOption({ label: 'Tell now' });
  await expect(page).toHaveURL(/outcome=tellnow/);
  await expect(rowsOf(page)).toHaveCount(2);
  const row = rowWith(page, `${tag} U3`);
  await row.getByRole('button').focus();
  await page.keyboard.press('Enter');
  await expect(row.getByRole('button')).toHaveAttribute('aria-expanded', 'true');
  await page.keyboard.press('Escape');
  await expect(row.getByRole('button')).toHaveAttribute('aria-expanded', 'false');
  await page.getByRole('button', { name: 'Clear filters', exact: true }).focus();
  await page.keyboard.press('Enter');
  await expect(page).not.toHaveURL(/outcome=|day=/);
  await expect(control(page, 'Outcome')).toBeFocused();
});

test('H12: the Incidents tab shows the Fallback flag, the no-summary text of a closed incident, its own pager, and its own failed read with Retry', async ({ page }) => {
  await openApp(page);
  const incidentOf = (index: number, extra: Record<string, unknown> = {}): Record<string, unknown> => ({
    ref: `ZzH12Ref${String(index).padStart(4, '0')}`,
    state: 'open',
    fallback: false,
    count: 1,
    firstAt: '2031-03-01T09:00:00Z',
    noticedAt: '2031-03-01T09:30:00Z',
    closedAt: '',
    summary: '',
    ...extra,
  });
  let failing = false;
  await page.route(INCIDENTS, (route) => {
    if (failing) return route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) });
    const second = new URL(route.request().url()).searchParams.get('page') === '2';
    const incidents = second
      ? [incidentOf(26)]
      : [incidentOf(1, { fallback: true }), incidentOf(2, { state: 'closed', closedAt: '2031-03-01T11:00:00Z' }), ...Array.from({ length: 23 }, (_one, index) => incidentOf(index + 3))];
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ page: second ? 2 : 1, pages: 2, incidents }) });
  });
  await visit(page, '?tab=incidents');
  await expect(incidentsOf(page)).toHaveCount(25);
  await expect(incidentsOf(page).nth(0).locator('.chip-row app-fallback-flag'), 'a fallback incident shows the Fallback flag by its chip').toHaveCount(1);
  await expect(incidentsOf(page).nth(2).locator('app-fallback-flag'), 'and one with no fallback none').toHaveCount(0);
  await expect(incidentsOf(page).nth(1).locator('app-incident-state-chip')).toHaveText('Closed');
  await expect(incidentsOf(page).nth(1), 'a closed incident with no summary says none was written').toContainText('No summary was written for this incident.');
  await expect(incidentsOf(page).nth(0)).toContainText('No summary yet. OcuTalon writes one when the incident closes.');

  const incidentPager = pager(page, 'Incident pages');
  await expect(incidentPager).toBeVisible();
  await expect(pager(page, 'Decision pages')).toHaveCount(0);
  await expect(incidentPager.getByText('Page 1 of 2', { exact: true })).toBeVisible();
  await incidentPager.getByRole('button', { name: 'Next page', exact: true }).click();
  await expect(page).toHaveURL(/page=2/);
  await expect(incidentsOf(page)).toHaveCount(1);
  await expect(page.getByText('Page 2 of 2', { exact: true })).toBeVisible();
  await expect(page.locator('main.history'), 'an incident page turn keeps keyboard focus on the page').toBeFocused();

  failing = true;
  await incidentPager.getByRole('button', { name: 'Previous page', exact: true }).click();
  await expect(failedOf(page)).toContainText(ERROR);
  await expect(incidentsOf(page)).toHaveCount(0);
  failing = false;
  await page.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(incidentsOf(page)).toHaveCount(25);
  await expect(failedOf(page), 'the error and Retry are gone with the answer').toHaveCount(0);
  await expectNoStaleError(page);
});

test.describe('in en-US', () => {
  test.use({ locale: 'en-US' });

  /** Chromium's date input reports a value for each digit of a year typed in (0002, 0020, 0202, 2026): only a readable day is a filter change. */
  test('H13: a date typed into the Date filter digit by digit is one filter change: one history entry, one read, no error', async ({ page }) => {
    await openApp(page);
    await visit(page, '');
    const asked: string[] = [];
    page.on('request', (request) => {
      if (request.url().includes('/api/v1/history/decisions') && request.url().includes('day=')) asked.push(request.url());
    });
    const before = await page.evaluate(() => window.history.length);
    const [year, month, day] = d45.split('-');
    await control(page, 'Date').focus();
    await page.keyboard.type(`${month}${day}${year}`, { delay: 50 });
    await expect(page).toHaveURL(new RegExp(`day=${d45}`));
    await expect(rowsOf(page)).toHaveCount(5);
    expect(asked, 'one read, with the typed day').toHaveLength(1);
    expect((await page.evaluate(() => window.history.length)) - before, 'one history entry').toBe(1);
    await expect(failedOf(page)).toHaveCount(0);
    await page.goBack();
    await expect(page).not.toHaveURL(/day=/);
  });
});

test.describe('in Europe/Berlin', () => {
  test.use({ timezoneId: 'Europe/Berlin', locale: 'en-GB' });

  /** The stack is in UTC: beside the headline, a time in the instance zone, the page times name the browser zone (EXPERIENCE: Formats). */
  test('H14: an incident row\'s Noticed and Closed times name the browser zone, and its headline time does not', async ({ page }) => {
    await openApp(page);
    await visit(page, '?tab=incidents');
    const closed = incidentsOf(page).filter({ hasText: 'No fix ran, so nothing was changed.' });
    await expect(closed).toHaveCount(1);
    await expect(closed.locator('.meta')).toContainText(/Noticed [^\n]*10:30[^\n]* CET/);
    await expect(closed.locator('.meta')).toContainText(/Closed [^\n]*12:00[^\n]* CET/);
    await expect(closed.locator('.headline')).toHaveText(/^4 orders failed since /);
    await expect(closed.locator('.headline')).not.toContainText('CET');
  });
});

/**
 * Runs the page's stopped clock (freeze) on in 20 ms steps until the check holds, and returns how far it ran. The page renders and its timers fire only on
 * these steps, so what a check waits for takes the same time of the page's clock on any host.
 */
async function stepUntil(page: Page, check: () => Promise<boolean>, most: number, what: string): Promise<number> {
  for (let ran = 0; ran <= most; ran += 20) {
    if (await check()) return ran;
    await page.clock.runFor(20);
  }
  throw new Error(`${what}: not within ${most} ms of the page's clock`);
}

/**
 * H15 needs the page's clock (page.clock.install() before sign-in), stopped before the first read: the second failure then waits for the live region's
 * one-second gap for as long as the test holds the clock, however slow the host, and the answer is handled before the clock runs again.
 */
test('H15: a failure that waits for the live region\'s one-second gap is not announced once a Retry has been answered', async ({ page }) => {
  await recordAnnouncements(page);
  await page.clock.install();
  await openApp(page);
  let asked = 0;
  let failed = 0;
  let answered = false;
  await page.route(DECISIONS, async (route) => {
    asked += 1;
    if (asked > 2) {
      await route.fulfill({ response: await route.fetch() });
      answered = true;
      return;
    }
    await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) });
    failed += 1;
  });
  await freeze(page);
  await page.evaluate((hash) => {
    window.location.hash = hash;
  }, `#/history?day=${d45}`);
  await stepUntil(page, async () => (await failedOf(page).count()) === 1 && (await announcements(page, ERROR)) === 1, 3000, 'the first failure shows and is announced');
  await expect(failedOf(page)).toContainText(ERROR);
  const retry = page.getByRole('button', { name: 'Retry', exact: true });
  await retry.press('Enter');
  await expect.poll(() => failed, 'the second read failed').toBe(2);
  await retry.press('Enter');
  await expect.poll(() => answered, 'the third read is answered').toBe(true);
  await stepUntil(page, async () => (await rowsOf(page).count()) === 5, 2000, 'the answer shows its five rows');
  await expect(failedOf(page)).toHaveCount(0);
  await page.clock.runFor(1500);
  expect(await announcements(page, ERROR), 'the second failure waited for the gap, and the answer withdrew it: the error was announced once').toBe(1);
});
