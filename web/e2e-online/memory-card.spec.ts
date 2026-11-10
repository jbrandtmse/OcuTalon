import { expect, test, type Locator, type Page } from '../e2e/support/fixtures';

import { loadedAfter, railOf } from '../e2e/support/floor';
import { announcements, recordAnnouncements } from '../e2e/support/page';
import { epochOf, removeSession, signInFromSplash, signOutGroup } from './support';

/**
 * Story 41.13 (FR-73, DW-1040, AD-25), the Memory card on the online demo (OM1 to OM3). The project runs on the online-demo throwaway. Every case signs out of the
 * whole sign-in group and removes the rows it made in `finally`. The texts are written out here, as the independent oracle of the page's own.
 * - OM1: the card shows the per-session rule under its tabs.
 * - OM2: a search answered 503 search_busy with Retry-After shows the card's own notice, announced once, and the page does not become busy: the "Demo busy" banner
 *   stays at 0.
 * - OM3: the control case: a 503 with the code busy on the same route is the page's busy state, and the banner shows.
 */
test.describe.configure({ timeout: 240_000 });

const DEMO_RULE =
  "On the online demo, your memories and pins belong to this visit: they're deleted when you sign out or the demo resets. Each search counts as one of your messages.";
const SEARCH_BUSY = 'Search is busy right now. Try again in a moment.';
const BANNER = '[data-banner="demoBusy"]';
const SEARCH = /\/api\/v1\/memory\/items\?q=/;

const card = (page: Page): Locator => railOf(page).locator('app-memory-card');
const memoriesTab = (page: Page): Locator => card(page).getByRole('tab', { name: 'All memories', exact: true });
const memoriesPanel = (page: Page): Locator => card(page).getByRole('tabpanel', { name: 'All memories', exact: true });
const searchBox = (page: Page): Locator => memoriesPanel(page).getByRole('searchbox', { name: 'Search your memories', exact: true });

/** Signs the demo account in at the page, waits for the loaded snapshot, and returns its epoch. */
async function open(page: Page): Promise<string> {
  await loadedAfter(page, () => signInFromSplash(page));
  return epochOf(page);
}

test('OM1: the card shows the online demo\'s per-session rule under its tabs', async ({ page }) => {
  let epoch = '';
  try {
    epoch = await open(page);
    await expect(card(page).getByRole('tab', { name: 'Notes', exact: true }), 'the card is drawn').toBeVisible();
    await expect(card(page).getByText(DEMO_RULE, { exact: true }), 'the rule line shows').toBeVisible();
    await memoriesTab(page).click();
    await expect(card(page).getByText(DEMO_RULE, { exact: true }), 'and stays on every tab').toHaveCount(1);
  } finally {
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});

test('OM2: a 503 search_busy on a search shows the card\'s own notice, and the page does not become busy', async ({ page }) => {
  let epoch = '';
  try {
    await recordAnnouncements(page);
    epoch = await open(page);
    let answered = 0;
    await page.route(SEARCH, async (route) => {
      answered += 1;
      await route.fulfill({ status: 503, headers: { 'retry-after': '5' }, json: { error: { code: 'search_busy', message: SEARCH_BUSY } } });
    });
    await memoriesTab(page).click();
    await expect(searchBox(page)).toBeVisible();
    await searchBox(page).fill('vpn');
    await searchBox(page).press('Enter');
    await expect.poll(() => answered, { message: 'the search was answered with 503' }).toBe(1);
    await expect(memoriesPanel(page).getByText(SEARCH_BUSY, { exact: true }), "the card shows its own busy notice").toBeVisible();
    await expect(searchBox(page), 'the box is described by it').toHaveAccessibleDescription(SEARCH_BUSY);
    await expect.poll(() => announcements(page, SEARCH_BUSY), { message: 'it is announced once' }).toBe(1);
    await page.waitForTimeout(1500);
    expect(await announcements(page, SEARCH_BUSY), 'and not again later').toBe(1);
    await expect(page.locator(BANNER), 'the page is not busy: the Demo busy banner stays at 0').toHaveCount(0);
  } finally {
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});

test('OM3: control: a 503 with the code busy on the same route is the page\'s busy state', async ({ page }) => {
  let epoch = '';
  try {
    epoch = await open(page);
    let answered = 0;
    await page.route(SEARCH, async (route) => {
      answered += 1;
      await route.fulfill({ status: 503, json: { error: { code: 'busy', message: 'Something went wrong inside OcuTalon. Try again.' } } });
    });
    await memoriesTab(page).click();
    await expect(searchBox(page)).toBeVisible();
    await searchBox(page).fill('vpn');
    await searchBox(page).press('Enter');
    await expect.poll(() => answered, { message: 'the search was answered with 503' }).toBe(1);
    await expect(page.locator(BANNER), 'the page shows the Demo busy banner').toHaveCount(1);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    await signOutGroup(page);
    if (epoch !== '') await removeSession(epoch);
  }
});
