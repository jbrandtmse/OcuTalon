import { expect, test, type Locator, type Page } from '../support/fixtures';

import { signIn } from '../sign-in/helpers';
import { phoneShows, raise, refOf, today } from '../support/approvals';
import { dropPhone } from '../support/devices';
import { CARD_MS, composerOf, inMs, loadedAfter, mainOf } from '../support/floor';
import { askedSlots, cleanFixtureRows, dropSettingChange, fixtureUser, seedApproval, seedIncident, seedSettingChange, sendNotification } from '../support/iris';
import { scanContrast, scanNames } from '../support/scan';
import { blockLiveSocket } from '../support/socket';

/**
 * Story 24.4a, the step-5 requests with a setting's value (F3b, F5, F5b and F7; Story 24.4b adds F1 to F4 and F6 to this file), in a real
 * browser against a real stack, as the rail fixture user (OCUTALON_RAIL_USER, whose session R1 to R19 of rail.spec.ts expect empty: each
 * case removes its rows, its setting changes and its phone messages in finally). The page's clock is fixed at 14:30 UTC on the run's date.
 * A value that holds a token is built from fragments here and read back from the server as `[redacted]` on every surface: the web
 * approval card (F3b), the evidence panel (F5b) and the phone page (F7); a plain value is shown byte for byte (F3b, F5). The page redacts
 * nothing: each of these is the server's text. F5 also scans the card in both schemes and tabs to Show details.
 */
test.describe.configure({ timeout: 120_000 });
test.use({ timezoneId: 'UTC', locale: 'en-GB' });

const KIND = 'RAIL';

/** The page's clock: 14:30 UTC on the run's date. */
test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(Date.parse(today('14:30:00')));
});

/** The token of the fixtures and the URL that holds it, from fragments (no key-like string stands in this file). */
const TOKEN = ['tk', 'z9', 'Q', 'w3'].join('');
const TOKEN_URL = `https://feed.example.test/orders?token=${TOKEN}`;
const SHOWN_URL = 'https://feed.example.test/orders?token=[redacted]';

/** The setting change of the incident: the item, the setting and the time it was detected, four minutes before the first failure. */
const ITEM = 'OrdersFromPartner';
const SETTING = 'TargetConfigName';

/** The incident card of a ref, the request card of a ref (both in the chat). */
const incidentCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="incident"][data-key="incident:${ref}"]`);
const requestCard = (page: Page, ref: string): Locator => page.locator(`app-chat-panel [data-part="approval"][data-key="${ref}"]`);

/** Signs the rail user in with the live socket closed, and waits for the loaded page with the phone. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await blockLiveSocket(page);
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

/** Opens the page with a live socket: the incident row that a case seeded comes with the snapshot. */
async function openLive(page: Page): Promise<void> {
  const { user, password } = fixtureUser(KIND);
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(composerOf(page)).toBeVisible();
}

/** The text of a card, to check that a token stands nowhere in it. */
const textOf = (locator: Locator): Promise<string> => locator.innerText();

/**
 * F3b: two pending rollback_setting requests with seeded dry runs, one whose After is a token URL and one with plain values. The card's
 * After row reads `...?token=[redacted]` for the first and holds no token anywhere in the card's text; the second shows its plain values
 * byte for byte. (The card's text is the server's: Approval.FromRow redacts Before and After.)
 */
test('F3b: a rollback card shows a token URL redacted and a plain value byte for byte', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  const incident = refOf('F3b');
  const requests: string[] = [];
  try {
    await open(page);
    const secret = await raise(page, user, rows, incident, requests, { fixKind: 'rollback_setting', dryRun: { item: ITEM, field: 'Host', before: 'OrdersRouterNew', after: TOKEN_URL } });
    const plain = await raise(page, user, rows, incident, requests, { fixKind: 'rollback_setting', dryRun: { item: ITEM, field: 'TargetConfigName', before: 'OrdersRouterNew', after: 'OrdersRouter' } });
    const secretCard = requestCard(page, secret);
    const plainCard = requestCard(page, plain);
    await expect(secretCard, 'the token request has a card').toHaveCount(1, { timeout: CARD_MS });
    await expect(plainCard, 'and so has the plain one').toHaveCount(1, { timeout: CARD_MS });
    await expect(secretCard.locator('.mono.after'), 'the token URL reads [redacted] after the token=').toHaveText(`Host: ${SHOWN_URL}`);
    await expect(secretCard.locator('.mono.before'), 'its plain Before is as it is').toHaveText('Host: OrdersRouterNew');
    expect(await textOf(secretCard), 'the card holds no token').not.toContain(TOKEN);
    await expect(plainCard.locator('.mono.before'), 'the plain request shows its values byte for byte').toHaveText('TargetConfigName: OrdersRouterNew');
    await expect(plainCard.locator('.mono.after')).toHaveText('TargetConfigName: OrdersRouter');
    expect(await textOf(plainCard), 'and no marker').not.toContain('[redacted]');
  } finally {
    await cleanFixtureRows(rows);
  }
});

/** The labels of an evidence panel, and its value lines, in order. */
async function panelOf(card: Locator): Promise<{ labels: string[]; values: Map<string, string> }> {
  const panel = card.locator('app-evidence-panel');
  const labels = await panel.locator('.label').allTextContents();
  const values = new Map<string, string>();
  for (const row of await panel.locator('.row').all()) {
    values.set(((await row.locator('.label').textContent()) ?? '').trim(), ((await row.locator('.value').first().textContent()) ?? '').trim());
  }
  return { labels, values };
}

/**
 * F5: an incident row that names a real setting change (seedIncident with settingChangeRef, first failure four minutes after the change)
 * carries the cause line and, after Show details, the Setting change, Old value, New value and Detected rows right after the Cause row,
 * the first three in mono. The card has no unnamed control and no contrast failure in the light and the dark scheme, and Tab reaches
 * Show details with a visible focus ring.
 */
test('F5: the evidence panel lists the setting change, and the card passes the scans in both schemes', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  let change = '';
  try {
    change = await seedSettingChange({ item: ITEM, setting: SETTING, oldValue: 'OrdersRouter', newValue: 'OrdersRouterNew', detectedAt: today('14:08:00') });
    const incident = await seedIncident(user, { state: 'awaiting_approval', firstAt: today('14:12:00'), settingChangeRef: change });
    rows.push(incident);
    await openLive(page);
    const card = incidentCard(page, incident);
    await expect(card, 'the incident has a card').toHaveCount(1, { timeout: CARD_MS });
    await expect(card.locator('.setting-cause-line'), 'the cause line names the change and the gap').toHaveText(`The feed broke four minutes after this setting changed: ${SETTING} on ${ITEM}, at 14:08.`);
    const details = card.getByRole('button', { name: 'Show details', exact: true });
    await details.click();
    const panel = card.locator('app-evidence-panel');
    await expect(panel).toBeVisible();
    const { labels, values } = await panelOf(card);
    const at = labels.indexOf('Setting change');
    expect(at, 'the rows come after the Cause row').toBeGreaterThan(labels.indexOf('Cause'));
    expect(labels.slice(at, at + 4), 'in order: the change, the old value, the new value, the time').toEqual(['Setting change', 'Old value', 'New value', 'Detected']);
    expect([values.get('Setting change'), values.get('Old value'), values.get('New value'), values.get('Detected')]).toEqual([`${SETTING} on ${ITEM}`, 'OrdersRouter', 'OrdersRouterNew', '14:08']);
    for (const label of ['Setting change', 'Old value', 'New value']) {
      await expect(panel.locator('.row').filter({ has: page.getByText(label, { exact: true }) }).locator('.value'), `${label} is mono`).toHaveClass(/mono/);
    }
    await expect(panel.locator('.row').filter({ has: page.getByText('Detected', { exact: true }) }).locator('.value'), 'the time is not mono').not.toHaveClass(/mono/);
    for (const scheme of ['light', 'dark'] as const) {
      await page.emulateMedia({ colorScheme: scheme });
      const what = `step 5 incident card, ${scheme}`;
      expect([...(await scanNames(page, what)), ...(await scanContrast(page, what))], what).toEqual([]);
    }
    await details.click();
    await expect(details).toHaveAttribute('aria-expanded', 'false');
    await composerOf(page).focus();
    let focused = false;
    for (let i = 0; i < 60 && !focused; i += 1) {
      await page.keyboard.press('Tab');
      focused = await details.evaluate((el) => el === document.activeElement);
    }
    expect(focused, 'Tab reaches Show details').toBe(true);
    await expect(details, 'with a visible focus ring').toHaveCSS('outline-style', 'solid');
    await expect(details).toHaveCSS('outline-width', '2px');
  } finally {
    await cleanFixtureRows(rows);
    if (change !== '') await dropSettingChange(change);
  }
});

/**
 * F5b: a non-secret setting change whose old value holds a token URL: the panel's Old value reads `...?token=[redacted]`, the card's
 * text holds no token, and the plain new value is as it is.
 */
test('F5b: the panel shows a token URL as [redacted]', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  let change = '';
  try {
    change = await seedSettingChange({ item: ITEM, setting: 'Host', oldValue: TOKEN_URL, newValue: 'OrdersRouterNew', detectedAt: today('14:08:00') });
    const incident = await seedIncident(user, { state: 'awaiting_approval', firstAt: today('14:12:00'), settingChangeRef: change });
    rows.push(incident);
    await openLive(page);
    const card = incidentCard(page, incident);
    await expect(card).toHaveCount(1, { timeout: CARD_MS });
    await card.getByRole('button', { name: 'Show details', exact: true }).click();
    await expect(card.locator('app-evidence-panel')).toBeVisible();
    const { values } = await panelOf(card);
    expect(values.get('Old value'), 'the old value reads [redacted] after the token=').toBe(SHOWN_URL);
    expect(values.get('New value'), 'the plain new value is as it is').toBe('OrdersRouterNew');
    expect(await textOf(card), 'the card holds no token').not.toContain(TOKEN);
  } finally {
    await cleanFixtureRows(rows);
    if (change !== '') await dropSettingChange(change);
  }
});

/**
 * F7: an undo notice whose slots come from the server's own fill (askedSlots: Watch.Notice.AskedSlots over a dry run with a token URL)
 * reads `...?token=[redacted]` on the phone page and holds no token.
 */
test('F7: the undo request on the phone page shows a token URL as [redacted]', async ({ page }) => {
  const { user } = fixtureUser(KIND);
  const rows: string[] = [];
  let change = '';
  const start = inMs(-2000);
  try {
    change = await seedSettingChange({ item: ITEM, setting: 'Host', oldValue: TOKEN_URL, newValue: 'OrdersRouterNew', detectedAt: today('14:08:00') });
    const incident = await seedIncident(user, { state: 'awaiting_approval', firstAt: today('14:12:00'), settingChangeRef: change });
    rows.push(incident);
    const dryRun = { item: ITEM, field: 'Host', before: 'OrdersRouterNew', after: TOKEN_URL };
    const request = await seedApproval(user, { fixKind: 'undo_rollback', incidentRef: incident, requiredRole: 'OcuTalonUser', dryRun });
    rows.push(request);
    const slots = await askedSlots('undo_rollback', { item: ITEM, field: 'Host', before: TOKEN_URL, after: 'OrdersRouterNew' }, incident);
    await openLive(page);
    await sendNotification(user, { kind: 'approval', catalogKey: 'incident.undoRollbackRequest', slots, approvalRef: request, incidentRef: incident });
    const { message } = await phoneShows(page, user, request);
    await expect(message, 'the phone shows the redacted URL').toContainText(SHOWN_URL);
    expect(await textOf(message), 'and no token').not.toContain(TOKEN);
  } finally {
    await dropPhone(user, start);
    await cleanFixtureRows(rows);
    if (change !== '') await dropSettingChange(change);
  }
});
