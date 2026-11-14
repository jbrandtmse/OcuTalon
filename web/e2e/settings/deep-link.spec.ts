import { expect, test, type Locator, type Page, type Response } from '../support/fixtures';

import { signInReadmeLoaded } from '../support/floor';
import { NAV_LINKS_ADMIN } from '../support/header-nav';

/**
 * Story 36.5, the lazily loaded Settings, History and Usage pages opened by their address (D1 to D4; the sign-in-2 unit), signed in as the README admin. Each case
 * signs in, then opens a NEW page in the same context at the page's hash (a real document load, so the router builds the lazy chunk from the address and not
 * from a link press), waits for the page's own GET to answer 200, checks the page, reloads it and checks it again. Every console error and page error from
 * before the first load is collected without a filter, so a lazy chunk that fails to load ("Failed to load resource") fails the case. The cases save nothing.
 *   D1  #/settings (titled Settings \u00B7 OcuTalon, the h1, the eight sections, Models, the header marks Settings) and #/settings/check-thresholds (its h2 and fields, its
 *       section link current);
 *   D2  #/history (titled History \u00B7 OcuTalon, the hidden h1, the tablist with Decisions selected, the header marks History);
 *   D3  #/usage (titled Usage \u00B7 OcuTalon, the h1, its table or its empty text, the header marks Usage);
 *   D4  (QA) the unsaved-changes guard on a lazy Settings page that was opened by its address: an edit left unsaved asks before a section link or a page link leaves,
 *       Stay keeps the section and the typed value, Leave without saving goes on (S6 reaches the page by link presses; here the chunk comes with the document load).
 */
const API = '/ocutalon/api/v1';
const SECTION_NAMES = ['Models', 'Budgets', 'Channels', 'Daily digest', 'Time zone', 'Check thresholds', 'On call', 'Demo mode'];
const THRESHOLD_LABELS = [
  'Disk free space below (%)',
  'Journal free space below (%)',
  'License use above (%)',
  'Queue backlog above (messages)',
  'Oldest queued message waiting over (minutes)',
];

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });

/** What a case records from a page before its first load: every console error and every page error. */
function recordErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(`console: ${message.text()}`);
  });
  page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
  return errors;
}

/** The address of the signed-in page with this hash. */
function addressOf(signedIn: Page, hash: string): string {
  const address = new URL(signedIn.url());
  address.hash = hash;
  return address.href;
}

/** Opens the hash in a NEW page of the signed-in page's context (a real document load) and returns it once the GET at `path` has answered, with the errors it recorded from before the load. */
async function open(signedIn: Page, hash: string, path: string): Promise<{ page: Page; errors: string[]; answered: Response }> {
  const page = await signedIn.context().newPage();
  const errors = recordErrors(page);
  const answered = page.waitForResponse((response) => response.request().method() === 'GET' && new URL(response.url()).pathname === `${API}${path}`);
  await page.goto(addressOf(signedIn, hash));
  return { page, errors, answered: await answered };
}

/** Reloads the page and waits for the GET at `path` to answer 200 again. */
async function reload(page: Page, path: string): Promise<void> {
  const answered = page.waitForResponse((response) => response.request().method() === 'GET' && new URL(response.url()).pathname === `${API}${path}`);
  await page.reload();
  expect((await answered).status(), `GET ${path} after the reload`).toBe(200);
}

/** The header marks exactly the page `current` of the admin's links as the current page. */
async function expectCurrent(page: Page, current: string): Promise<void> {
  const nav = pagesNav(page);
  await expect(nav.getByRole('link'), 'the header holds the links of an admin').toHaveText(NAV_LINKS_ADMIN);
  for (const name of NAV_LINKS_ADMIN) {
    const link = nav.getByRole('link', { name, exact: true });
    if (name === current) {
      await expect(link, `${name} is the current page`).toHaveAttribute('aria-current', 'page');
    } else {
      await expect(link, `${name} is not the current page`).not.toHaveAttribute('aria-current', 'page');
    }
  }
}

async function expectSettings(page: Page): Promise<void> {
  await expect(page, 'titled Settings').toHaveTitle('Settings \u00B7 OcuTalon');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Settings');
  await expect(sectionsNav(page).getByRole('link'), 'the eight sections').toHaveText(SECTION_NAMES);
  await expect(page.getByRole('heading', { level: 2 }), '#/settings opens Models').toHaveText('Models');
  await expectCurrent(page, 'Settings');
}

async function expectThresholds(page: Page): Promise<void> {
  await expect(page, 'titled Settings').toHaveTitle('Settings \u00B7 OcuTalon');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Settings');
  await expect(sectionsNav(page).getByRole('link'), 'the eight sections').toHaveText(SECTION_NAMES);
  await expect(page.getByRole('heading', { level: 2 }), 'the section of the address').toHaveText('Check thresholds');
  await expect(sectionsNav(page).getByRole('link', { name: 'Check thresholds', exact: true }), 'its link is current').toHaveAttribute('aria-current', 'true');
  for (const label of THRESHOLD_LABELS) {
    await expect(page.getByLabel(label, { exact: true }), `the field ${label}`).toBeVisible();
  }
  await expectCurrent(page, 'Settings');
}

async function expectHistory(page: Page): Promise<void> {
  await expect(page, 'titled History').toHaveTitle('History \u00B7 OcuTalon');
  await expect(page.getByRole('heading', { level: 1, name: 'History' }), 'the h1 (visually hidden)').toHaveCount(1);
  await expect(page.getByRole('tablist')).toHaveAccessibleName('History');
  await expect(page.getByRole('tab', { name: 'Decisions', exact: true }), 'Decisions is selected').toHaveAttribute('aria-selected', 'true');
  await expectCurrent(page, 'History');
}

async function expectUsage(page: Page): Promise<void> {
  await expect(page, 'titled Usage').toHaveTitle('Usage \u00B7 OcuTalon');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Usage');
  await expect(page.locator('main.usage').locator('table.table, p.empty').first(), 'its table or its empty text').toBeVisible();
  await expectCurrent(page, 'Usage');
}

test('D1: #/settings and #/settings/check-thresholds open the lazy Settings page by address, and again after a reload', async ({ page }) => {
  await signInReadmeLoaded(page);
  for (const [hash, check] of [
    ['#/settings', expectSettings],
    ['#/settings/check-thresholds', expectThresholds],
  ] as const) {
    const { page: linked, errors, answered } = await open(page, hash, '/settings');
    expect(answered.status(), `GET /settings for ${hash}`).toBe(200);
    await check(linked);
    await reload(linked, '/settings');
    await check(linked);
    expect(errors, `no console error or page error at ${hash}`).toEqual([]);
    await linked.close();
  }
});

test('D2: #/history opens the lazy History page by address, and again after a reload', async ({ page }) => {
  await signInReadmeLoaded(page);
  const { page: linked, errors, answered } = await open(page, '#/history', '/history/decisions');
  expect(answered.status(), 'GET /history/decisions').toBe(200);
  await expectHistory(linked);
  await reload(linked, '/history/decisions');
  await expectHistory(linked);
  expect(errors, 'no console error or page error at #/history').toEqual([]);
  await linked.close();
});

test('D3: #/usage opens the lazy Usage page by address, and again after a reload', async ({ page }) => {
  await signInReadmeLoaded(page);
  const { page: linked, errors, answered } = await open(page, '#/usage', '/usage');
  expect(answered.status(), 'GET /usage').toBe(200);
  await expectUsage(linked);
  await reload(linked, '/usage');
  await expectUsage(linked);
  expect(errors, 'no console error or page error at #/usage').toEqual([]);
  await linked.close();
});

test('D4: an unsaved edit on the Settings page opened by address still asks before a link leaves it', async ({ page }) => {
  await signInReadmeLoaded(page);
  const { page: linked, errors, answered } = await open(page, '#/settings/check-thresholds', '/settings');
  expect(answered.status(), 'GET /settings').toBe(200);
  await expectThresholds(linked);
  const disk = linked.getByLabel(THRESHOLD_LABELS[0], { exact: true });
  const saved = await disk.inputValue();
  const typed = saved === '41' ? '42' : '41';
  const dialog = linked.getByRole('dialog');
  await expect(dialog, 'a clean form asks nothing yet').toHaveCount(0);
  await disk.fill(typed);

  await sectionsNav(linked).getByRole('link', { name: 'Demo mode', exact: true }).click();
  await expect(dialog, 'a section link asks first').toBeVisible();
  await expect(dialog).toContainText('You have unsaved changes in this section. Leave without saving?');
  await dialog.getByRole('button', { name: 'Stay', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(linked, 'Stay keeps the section').toHaveURL(/#\/settings\/check-thresholds$/);
  await expect(disk, 'and the typed value').toHaveValue(typed);

  await pagesNav(linked).getByRole('link', { name: 'Chat', exact: true }).click();
  await expect(dialog, 'a page link asks first too').toBeVisible();
  await dialog.getByRole('button', { name: 'Leave without saving', exact: true }).click();
  await expect(linked, 'Leave goes on to the chat').not.toHaveURL(/#\/settings/);
  expect(errors, 'no console error or page error').toEqual([]);
  await linked.close();
});
