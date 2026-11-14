import { expect, test, type Locator, type Page, type Route } from '../support/fixtures';

import { README_ACCOUNT, envelope, signIn, signInOverHttp } from '../sign-in/helpers';
import { loadedAfter, signInReadmeLoaded } from '../support/floor';
import { NAV_LINKS_ADMIN } from '../support/header-nav';
import { announcements, recordAnnouncements } from '../support/page';
import { adminAtSignIn, fixtureUser } from '../support/iris';

/**
 * Story 33.2, the settings page for an admin (S1 to S8, with S1t, S1f, S3b, S4b, S5b, S6b, S6c, S7b and S7c), in a real browser against a real stack: the README account holds OcuTalonAdmin, and the live
 * fixture user (OCUTALON_LIVE_USER, test-sign-in.sh) holds OcuTalonUser only. The cases that save restore the five thresholds they change. Story 18.3 adds S13 (Models)
 * and S14 (Budgets): every case puts back the prices, budgets or models it changes. Story 35.2 adds S15 (the admin flag of a real sign-in), which
 * leaves the README account's Session.AdminAtSignIn at 1 and the live fixture user's at 0, the values their own sign-ins write.
 */
const SETTINGS = '/ocutalon/api/v1/settings';
const SECTIONS = ['check-thresholds', 'budgets', 'models', 'channels', 'daily-digest', 'time-zone', 'demo-mode', 'mcp'] as const;
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const DEMO_SAVED = 'Saved. Applies within a minute. Recorded in the audit log. Reload the chat page after a minute to see the change.';
const FAILED = "Couldn't save. Nothing was changed.";
const BUSY_NOTICE = "Couldn't reach OcuTalon. Try again. Nothing was changed.";
const DENIED = 'Only OcuTalon admins can open settings.';
const FIELDS = {
  diskFreePercent: 'Disk free space below (%)',
  journalFreePercent: 'Journal free space below (%)',
  licenseUsePercent: 'License use above (%)',
  queueMessages: 'Queue backlog above (messages)',
  queueWaitMinutes: 'Oldest queued message waiting over (minutes)',
} as const;

type Thresholds = Record<keyof typeof FIELDS, number>;

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });
const saveButton = (page: Page): Locator => page.getByRole('button', { name: 'Save changes', exact: true });
/** The section's own saved line, not the announcer's copy of it. */
const savedText = (page: Page): Locator => page.locator('p.saved').filter({ hasText: SAVED });
const field = (page: Page, name: keyof typeof FIELDS): Locator => page.getByLabel(FIELDS[name], { exact: true });

/** The thresholds the server holds now, from GET /v1/settings (read through the page's own session). */
async function thresholds(page: Page): Promise<Thresholds> {
  const response = await page.request.get(SETTINGS);
  expect(response.status(), 'GET /v1/settings as an admin').toBe(200);
  const body = (await response.json()) as { sections: { 'check-thresholds': Thresholds } };
  return body.sections['check-thresholds'];
}

/** Puts the thresholds back through the API, with the envelope of a state-changing call. */
async function restore(page: Page, values: Thresholds): Promise<void> {
  const response = await page.request.post(`${SETTINGS}/check-thresholds`, { headers: envelope(), data: values });
  expect(response.status(), 'the thresholds are restored').toBe(200);
}

/** Signs the README admin in, opens Settings from the header and the Check thresholds section from the navigation. */
async function openThresholds(page: Page): Promise<void> {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Check thresholds', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Check thresholds' })).toBeVisible();
  await expect(field(page, 'diskFreePercent')).toBeVisible();
}

/** S1: the header navigation, the title and the eight sections in the UX's order. */
test('S1: an admin sees Chat and Settings in the header, and Settings opens the page with its eight sections', async ({ page }) => {
  await signInReadmeLoaded(page);
  const guide = page.getByRole('region', { name: 'Demo guide' });
  await expect(guide, 'the main page has the demo guide (demo mode on)').toHaveCount(1);
  const nav = pagesNav(page);
  await expect(nav, 'the header holds one navigation landmark named Pages').toHaveCount(1);
  await expect(nav.getByRole('link'), 'with the links of an admin').toHaveText(NAV_LINKS_ADMIN);
  await expect(nav.getByRole('link', { name: 'Chat', exact: true }), 'the current page is marked').toHaveAttribute('aria-current', 'page');
  await expect(nav.getByRole('link', { name: 'Settings', exact: true })).not.toHaveAttribute('aria-current', 'page');

  let loads = 0;
  page.on('request', (request) => {
    if (request.method() === 'GET' && new URL(request.url()).pathname === SETTINGS) loads += 1;
  });
  await nav.getByRole('link', { name: 'Settings', exact: true }).click();
  await expect(page, 'at the address #/settings').toHaveURL(/#\/settings$/);
  await expect(nav.getByRole('link', { name: 'Settings', exact: true }), 'Settings is now the current page').toHaveAttribute('aria-current', 'page');
  await expect(nav.getByRole('link', { name: 'Chat', exact: true })).not.toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('heading', { level: 1 }), 'one h1').toHaveText('Settings');
  await expect(sectionsNav(page).getByRole('link'), 'the sections, in the UX order').toHaveText(['Models', 'Budgets', 'Channels', 'Daily digest', 'Time zone', 'Check thresholds', 'Demo mode', 'Tools and MCP servers']);
  await expect(page.getByRole('heading', { level: 2 }), '#/settings opens Models').toHaveText('Models');
  await expect(page.getByText("This part of OcuTalon isn't built yet."), 'Models is built').toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Save changes' }), 'Models has its Save changes button').toHaveCount(1);
  await expect(page.getByRole('link', { name: 'Skip to chat', exact: true }), 'the skip links belong to the main page').toHaveCount(0);
  await expect(guide, 'and so does the demo guide').toHaveCount(0);

  for (const [slug, label] of [['budgets', 'Budgets'], ['channels', 'Channels'], ['daily-digest', 'Daily digest'], ['time-zone', 'Time zone'], ['check-thresholds', 'Check thresholds'], ['demo-mode', 'Demo mode'], ['mcp', 'Tools and MCP servers'], ['models', 'Models']] as const) {
    const link = sectionsNav(page).getByRole('link', { name: label, exact: true });
    await link.focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('heading', { level: 2 })).toHaveText(label);
    expect(new URL(page.url()).hash, `${label} has its own address`).toBe(`#/settings/${slug}`);
    await expect(link).toHaveAttribute('aria-current', 'true');
    await expect(link, `the ${label} link keeps the keyboard focus: the page is not built again`).toBeFocused();
    await expect(page.getByText("This part of OcuTalon isn't built yet."), `${label} is built: no section shows the not-built text`).toHaveCount(0);
  }
  expect(loads, 'a section change keeps the page: GET /v1/settings was asked once').toBe(1);
  await page.evaluate(() => {
    location.hash = '#/settings/zz-unknown';
  });
  await expect(page.getByRole('heading', { level: 2 }), 'an unknown section opens Models').toHaveText('Models');

  await nav.getByRole('link', { name: 'Chat', exact: true }).click();
  await expect(page.locator('main.main'), 'Chat returns to the main page').toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.getByRole('link', { name: 'Skip to chat', exact: true }), 'and its skip links').toHaveCount(1);
  await expect(guide, 'and its demo guide').toHaveCount(1);
});

/** S1t: the page is titled Settings \u00B7 OcuTalon, and the main page OcuTalon again after Chat. */
test('S1t: the settings page is titled Settings \u00B7 OcuTalon', async ({ page }) => {
  await signInReadmeLoaded(page);
  await expect(page, 'the main page is titled OcuTalon').toHaveTitle('OcuTalon');
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await expect(page, 'the page is titled Settings \u00B7 OcuTalon').toHaveTitle('Settings \u00B7 OcuTalon');
  await pagesNav(page).getByRole('link', { name: 'Chat', exact: true }).click();
  await expect(page, 'Chat returns to the title OcuTalon').toHaveTitle('OcuTalon');
});

/** S1f: a page whose GET /v1/settings fails shows the load error with Retry, and Retry loads the sections. */
test('S1f: a failed load shows the load error, and Retry loads the page', async ({ page }) => {
  await signInReadmeLoaded(page);
  let failures = 1;
  await page.route('**/api/v1/settings', (route) =>
    route.request().method() === 'GET' && failures-- > 0
      ? route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) })
      : route.continue(),
  );
  try {
    await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
    await expect(page.locator('main[data-settings]'), 'the load failed').toHaveAttribute('data-settings', 'failed');
    await expect(page.locator('p.load-error-text')).toHaveText("Couldn't load your session.");
    await expect(sectionsNav(page), 'no sections').toHaveCount(0);
    await page.getByRole('button', { name: 'Retry', exact: true }).click();
    await expect(page.getByRole('heading', { level: 2 }), 'Retry loads the page').toHaveText('Models');
    await expect(sectionsNav(page).getByRole('link')).toHaveCount(8);
  } finally {
    await page.unroute('**/api/v1/settings');
  }
});

/** S2: a save of two thresholds is written, shown, announced and read back by GET /v1/settings. */
test('S2: saving two thresholds shows the saved text, and GET /v1/settings returns the new values', async ({ page }) => {
  await recordAnnouncements(page);
  await openThresholds(page);
  const before = await thresholds(page);
  try {
    for (const name of Object.keys(FIELDS) as Array<keyof typeof FIELDS>) {
      await expect(field(page, name), `${name} shows the server's value`).toHaveValue(String(before[name]));
    }
    const diskFree = before.diskFreePercent === 17 ? 18 : 17;
    const queue = before.queueMessages === 321 ? 322 : 321;
    await field(page, 'diskFreePercent').fill(String(diskFree));
    await field(page, 'queueMessages').fill(String(queue));
    await saveButton(page).click();
    await expect(savedText(page), 'the saved text shows').toBeVisible();
    await expect(page.locator('p.saved'), 'and it is exactly the shared text, without the Demo mode sentence').toHaveText(SAVED);
    await expect.poll(() => announcements(page, SAVED), 'the shared text is announced').toBe(1);
    expect(await announcements(page, DEMO_SAVED), 'never the Demo mode text').toBe(0);
    await expect(page.getByText(FAILED), 'and no error').toHaveCount(0);
    const after = await thresholds(page);
    expect(after.diskFreePercent, 'GET shows the first new value at once').toBe(diskFree);
    expect(after.queueMessages, 'and the second').toBe(queue);
    expect(after.journalFreePercent, 'the others are as they were').toBe(before.journalFreePercent);

    await field(page, 'queueWaitMinutes').fill(String(before.queueWaitMinutes + 1));
    await expect(savedText(page), 'typing again clears the saved text').toHaveCount(0);
    await field(page, 'queueWaitMinutes').fill(String(before.queueWaitMinutes));
    await page.reload();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Settings');
    await sectionsNav(page).getByRole('link', { name: 'Check thresholds', exact: true }).click();
    await expect(field(page, 'diskFreePercent'), 'a reload shows the saved value, not the old one').toHaveValue(String(diskFree));
  } finally {
    await restore(page, before);
  }
});

/** S3: a refused value shows the field error, linked and focused, and changes nothing. */
test('S3: a value the server refuses shows the field error on that field, focused, and nothing changes', async ({ page }) => {
  await openThresholds(page);
  const before = await thresholds(page);
  try {
    for (const bad of ['abc', '101', '@{env:KEY}']) {
      await field(page, 'diskFreePercent').fill(bad);
      await field(page, 'queueMessages').fill('250');
      await saveButton(page).click();
      const input = field(page, 'diskFreePercent');
      await expect(page.locator('#threshold-diskFreePercent-error'), `'${bad}' shows the field error`).toHaveText(FAILED);
      await expect(input, 'the field is marked invalid').toHaveAttribute('aria-invalid', 'true');
      await expect(input, 'and linked to its error').toHaveAttribute('aria-describedby', 'threshold-diskFreePercent-error');
      await expect(input, 'and focused').toBeFocused();
      await expect(page.locator('#threshold-queueMessages-error'), 'the other field has none').toHaveCount(0);
      expect((await thresholds(page)).queueMessages, `'${bad}': nothing was written, though the other field was fine`).toBe(before.queueMessages);
      await field(page, 'diskFreePercent').fill(String(before.diskFreePercent));
      await field(page, 'queueMessages').fill(String(before.queueMessages));
    }
  } finally {
    await restore(page, before);
  }
});

/** S3b: with two refused values, both fields show the error, and the first one in the form's order takes focus (not the one typed first or last). */
test('S3b: two refused values mark both fields and focus the first in the form', async ({ page }) => {
  await openThresholds(page);
  const before = await thresholds(page);
  try {
    await field(page, 'queueWaitMinutes').fill('abc');
    await field(page, 'licenseUsePercent').fill('0');
    await saveButton(page).click();
    await expect(page.locator('#threshold-licenseUsePercent-error'), 'the first refused field shows the error').toHaveText(FAILED);
    await expect(page.locator('#threshold-queueWaitMinutes-error'), 'so does the second').toHaveText(FAILED);
    await expect(page.locator('#threshold-diskFreePercent-error'), 'a field that was fine has none').toHaveCount(0);
    await expect(field(page, 'licenseUsePercent'), 'the first in the form takes focus').toBeFocused();
    await expect(field(page, 'queueWaitMinutes'), 'the second is marked invalid').toHaveAttribute('aria-invalid', 'true');
    expect(await thresholds(page), 'nothing was written').toEqual(before);
  } finally {
    await restore(page, before);
  }
});

/** S4: a failed save (a held 500) shows the error under the button, linked to it, and the button follows the busy pattern. */
test('S4: a failed save shows the error under the button', async ({ page }) => {
  await openThresholds(page);
  await page.route('**/api/v1/settings/check-thresholds', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.continue();
      return;
    }
    await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } }) });
  });
  const before = await thresholds(page);
  await field(page, 'diskFreePercent').fill(String(before.diskFreePercent === 20 ? 21 : 20));
  await saveButton(page).click();
  await expect(page.locator('#thresholds-error'), 'the error is under the button').toHaveText(FAILED);
  await expect(saveButton(page), 'the button is described by it').toHaveAttribute('aria-describedby', 'thresholds-error');
  await expect(saveButton(page), 'and is restored').not.toHaveAttribute('aria-busy', 'true');
  await expect(savedText(page), 'no saved text').toHaveCount(0);
});

/** S4b: a save answered 403 (the user is no longer an admin) shows the denied view, which leaves without asking about the unsaved form. */
test('S4b: a save answered 403 shows the denied view, and Back to the chat leaves without asking', async ({ page }) => {
  await openThresholds(page);
  await page.route('**/api/v1/settings/check-thresholds', (route) =>
    route.request().method() === 'POST'
      ? route.fulfill({ status: 403, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_admin', message: DENIED } }) })
      : route.continue(),
  );
  try {
    const before = await thresholds(page);
    await field(page, 'diskFreePercent').fill(String(before.diskFreePercent === 20 ? 21 : 20));
    await saveButton(page).click();
    await expect(page.locator('p.denied'), 'the denied view').toHaveText(DENIED);
    await page.getByRole('link', { name: 'Back to the chat', exact: true }).click();
    await expect(page.locator('main.main'), 'Back to the chat leaves').toHaveAttribute('data-snapshot', 'loaded');
    await expect(page.getByRole('dialog'), 'with nothing left unsaved to ask about').toHaveCount(0);
  } finally {
    await page.unroute('**/api/v1/settings/check-thresholds');
  }
});

/** S5: with no answer the button is busy, then restored with the notice after 10 s, and a late answer still shows. */
test('S5: a held save is busy, then shows the busy notice, and the late answer still shows', async ({ page }) => {
  test.setTimeout(75_000);
  await openThresholds(page);
  const before = await thresholds(page);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  await page.route('**/api/v1/settings/check-thresholds', async (route) => {
    if (route.request().method() === 'POST') await gate;
    await route.continue().catch(() => undefined);
  });
  try {
    await field(page, 'queueWaitMinutes').fill(String(before.queueWaitMinutes === 33 ? 34 : 33));
    await saveButton(page).click();
    await expect(saveButton(page), 'the button is busy').toHaveAttribute('aria-busy', 'true');
    await expect(saveButton(page), 'and aria-disabled, never disabled').toHaveAttribute('aria-disabled', 'true');
    await expect(page.locator('[id^="server-button-notice"]').filter({ hasText: BUSY_NOTICE }), 'after 10 s the notice shows').toBeVisible({ timeout: 20_000 });
    await expect(saveButton(page), 'and the button is restored').not.toHaveAttribute('aria-busy', 'true');
    release();
    await expect(savedText(page), 'the late answer still shows').toBeVisible();
    await expect(page.locator('[id^="server-button-notice"]').filter({ hasText: BUSY_NOTICE }), 'and clears the notice').toHaveCount(0);
  } finally {
    release();
    await page.unroute('**/api/v1/settings/check-thresholds');
    await restore(page, before);
  }
});

/** S5b: a field edited while a save is pending keeps its value when the answer comes, shows no saved text and stays unsaved. */
test('S5b: an edit made while the save is pending is kept and stays unsaved', async ({ page }) => {
  await openThresholds(page);
  const before = await thresholds(page);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  await page.route('**/api/v1/settings/check-thresholds', async (route) => {
    if (route.request().method() === 'POST') await gate;
    await route.continue().catch(() => undefined);
  });
  try {
    const typed = before.diskFreePercent === 40 ? 41 : 40;
    await field(page, 'queueWaitMinutes').fill(String(before.queueWaitMinutes === 33 ? 34 : 33));
    await saveButton(page).click();
    await expect(saveButton(page), 'the save is pending').toHaveAttribute('aria-busy', 'true');
    await field(page, 'diskFreePercent').fill(String(typed));
    const answered = page.waitForResponse((response) => response.url().endsWith('/v1/settings/check-thresholds') && response.request().method() === 'POST');
    release();
    expect((await answered).status(), 'the save answers').toBe(200);
    await expect(saveButton(page), 'and the button is restored').not.toHaveAttribute('aria-busy', 'true');
    await expect(field(page, 'diskFreePercent'), 'the edit made meanwhile is kept').toHaveValue(String(typed));
    await expect(savedText(page), 'no saved text shows for a form that is still unsaved').toHaveCount(0);
    await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog, 'the form is still unsaved, so a section link asks first').toBeVisible();
    await dialog.getByRole('button', { name: 'Leave without saving', exact: true }).click();
    expect((await thresholds(page)).diskFreePercent, 'the edit made meanwhile was not saved').toBe(before.diskFreePercent);
  } finally {
    release();
    await page.unroute('**/api/v1/settings/check-thresholds');
    await restore(page, before);
  }
});

/** S6: leaving a section with unsaved changes asks first; Stay keeps the values, Leave discards them; the browser's own prompt is armed while dirty. */
test('S6: unsaved changes ask before a link leaves, and only Leave discards them', async ({ page }) => {
  await openThresholds(page);
  const before = await thresholds(page);
  const prevented = (): Promise<boolean> =>
    page.evaluate(() => {
      const event = new Event('beforeunload', { cancelable: true });
      window.dispatchEvent(event);
      return event.defaultPrevented;
    });
  expect(await prevented(), 'a clean form arms no prompt').toBe(false);
  await field(page, 'diskFreePercent').fill(String(before.diskFreePercent === 40 ? 41 : 40));
  expect(await prevented(), 'a dirty form arms the browser\'s own prompt').toBe(true);

  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog, 'a section link asks first').toBeVisible();
  await expect(dialog).toContainText('You have unsaved changes in this section. Leave without saving?');
  await expect(dialog.getByRole('button', { name: 'Stay', exact: true }), 'Stay has the first focus').toBeFocused();
  await dialog.getByRole('button', { name: 'Stay', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  expect(new URL(page.url()).hash, 'Stay keeps the section').toBe('#/settings/check-thresholds');
  await expect(field(page, 'diskFreePercent'), 'and the typed value').toHaveValue(String(before.diskFreePercent === 40 ? 41 : 40));

  await pagesNav(page).getByRole('link', { name: 'Chat', exact: true }).click();
  await expect(dialog, 'the Chat link asks first too').toBeVisible();
  await page.keyboard.press('Escape');
  await expect(dialog, 'Escape is Stay').toHaveCount(0);
  expect(new URL(page.url()).hash).toBe('#/settings/check-thresholds');

  await page.goBack();
  await expect(dialog, 'the browser\'s back asks first').toBeVisible();
  await dialog.getByRole('button', { name: 'Stay', exact: true }).click();

  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  await dialog.getByRole('button', { name: 'Leave without saving', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2 })).toHaveText('Demo mode');
  expect(await prevented(), 'leaving clears the prompt').toBe(false);
  await sectionsNav(page).getByRole('link', { name: 'Check thresholds', exact: true }).click();
  await expect(field(page, 'diskFreePercent'), 'the discarded value is gone').toHaveValue(String(before.diskFreePercent));
  expect((await thresholds(page)).diskFreePercent, 'and was never saved').toBe(before.diskFreePercent);
});

/** S6c: a browser back that the user answers with Stay keeps the history as it was: a second back still goes to the page before. */
test('S6c: Stay on the browser back keeps the history, and a second back leaves to the page before', async ({ page }) => {
  await openThresholds(page);
  const before = await thresholds(page);
  await field(page, 'diskFreePercent').fill(String(before.diskFreePercent === 40 ? 41 : 40));
  const dialog = page.getByRole('dialog');
  await page.goBack();
  await expect(dialog, 'the browser\'s back asks first').toBeVisible();
  await dialog.getByRole('button', { name: 'Stay', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(page, 'Stay keeps the section').toHaveURL(/#\/settings\/check-thresholds$/);
  await page.goBack();
  await expect(dialog, 'a second back asks again').toBeVisible();
  await dialog.getByRole('button', { name: 'Leave without saving', exact: true }).click();
  await expect(page, 'and goes to the page before the section, #/settings').toHaveURL(/#\/settings$/);
  await expect(page.getByRole('heading', { level: 2 })).toHaveText('Models');
  expect((await thresholds(page)).diskFreePercent, 'nothing was saved').toBe(before.diskFreePercent);
});

/** S6b: an unsaved Demo mode switch asks before a section link leaves, and switching it back to the saved value is clean. */
test('S6b: an unsaved Demo mode switch asks before leaving, and is clean again when switched back', async ({ page }) => {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  const toggle = page.getByRole('switch', { name: /^Demo mode/ });
  await expect(toggle).toBeVisible();
  const was = (await toggle.getAttribute('aria-checked')) === 'true';
  const dialog = page.getByRole('dialog');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', String(!was));
  await sectionsNav(page).getByRole('link', { name: 'Check thresholds', exact: true }).click();
  await expect(dialog, 'a changed switch asks before a section link leaves').toBeVisible();
  await expect(dialog).toContainText('You have unsaved changes in this section. Leave without saving?');
  await dialog.getByRole('button', { name: 'Stay', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  expect(new URL(page.url()).hash, 'Stay keeps the section').toBe('#/settings/demo-mode');
  await expect(toggle, 'and the changed switch').toHaveAttribute('aria-checked', String(!was));
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', String(was));
  await sectionsNav(page).getByRole('link', { name: 'Check thresholds', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Check thresholds' }), 'switched back, nothing is unsaved: the link leaves').toBeVisible();
  await expect(dialog).toHaveCount(0);
});

/** S7: the Demo mode section shows the switch with its state and help, and a refused save shows the field error on it. */
test('S7: the Demo mode section has a switch, its help line and Save changes, and a failed save shows the field error', async ({ page }) => {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  const toggle = page.getByRole('switch', { name: /^Demo mode/ });
  await expect(toggle).toBeVisible();
  await expect(page.getByText('Demo mode adds the demo guide, Break the feed, and the simulated devices.')).toBeVisible();
  await expect(toggle, 'described by the help line').toHaveAttribute('aria-describedby', /demo-mode-help/);
  const was = (await toggle.getAttribute('aria-checked')) === 'true';
  await expect(toggle, 'the switch shows On or Off').toContainText(was ? 'On' : 'Off');
  await page.route('**/api/v1/settings/demo-mode', (route) =>
    route.request().method() === 'POST'
      ? route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) })
      : route.continue(),
  );
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-checked', String(!was));
  await saveButton(page).click();
  await expect(page.locator('#demo-mode-error'), 'the field error').toHaveText(FAILED);
  await expect(toggle, 'linked to the switch').toHaveAttribute('aria-describedby', /demo-mode-error/);
  await expect(toggle, 'which takes focus').toBeFocused();
  await page.unroute('**/api/v1/settings/demo-mode');
});

/** S7b: a Demo step that failed after the value was written (409 demo_step_failed) keeps the value and shows the ruled text, never "Nothing was changed.". */
test('S7b: a failed Demo step shows its own text and keeps the written value', async ({ page }) => {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  const toggle = page.getByRole('switch', { name: /^Demo mode/ });
  await expect(toggle).toBeVisible();
  const was = (await toggle.getAttribute('aria-checked')) === 'true';
  await page.route('**/api/v1/settings/demo-mode', (route) =>
    route.request().method() === 'POST'
      ? route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ error: { code: 'demo_step_failed', message: 'x' } }) })
      : route.continue(),
  );
  try {
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', String(!was));
    await saveButton(page).click();
    const word = was ? 'off' : 'on';
    await expect(page.locator('#demo-mode-error'), 'the ruled text for the value that was written').toHaveText(
      `Demo mode is set to ${word}, but the switch didn't finish. OcuTalon tries again at its next start.`,
    );
    await expect(page.locator('#demo-mode-error'), 'never the text that says nothing changed').not.toContainText('Nothing was changed.');
    await expect(toggle, 'the switch keeps the written value').toHaveAttribute('aria-checked', String(!was));
  } finally {
    await page.unroute('**/api/v1/settings/demo-mode');
  }
});

/** S7c: a saved Demo mode shows and announces its own confirmation, which adds the reload sentence (DW-699); the 200 is stubbed like S7 and S7b, so the real mode is not changed. */
test('S7c: a Demo mode save shows and announces its own confirmation with the reload sentence', async ({ page }) => {
  await recordAnnouncements(page);
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  const toggle = page.getByRole('switch', { name: /^Demo mode/ });
  await expect(toggle).toBeVisible();
  const was = (await toggle.getAttribute('aria-checked')) === 'true';
  await page.route('**/api/v1/settings/demo-mode', (route) =>
    route.request().method() === 'POST'
      ? route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ result: 'done', sections: { 'demo-mode': { demoMode: !was } } }),
        })
      : route.continue(),
  );
  try {
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', String(!was));
    await saveButton(page).click();
    await expect(page.locator('p.saved'), "the section's own confirmation").toHaveText(DEMO_SAVED);
    await expect.poll(() => announcements(page, DEMO_SAVED), 'it is announced').toBe(1);
    await page.waitForTimeout(2500);
    expect(await announcements(page, DEMO_SAVED), 'and announced once').toBe(1);
  } finally {
    await page.unroute('**/api/v1/settings/demo-mode');
  }
});

/** S8: a user without OcuTalonAdmin sees no Settings link, the denied view at #/settings, and 403 not_admin on all nine settings calls. */
test('S8: a user without OcuTalonAdmin is denied', async ({ page }) => {
  const { user, password } = fixtureUser('LIVE');
  await loadedAfter(page, () => signIn(page, user, password));
  const nav = pagesNav(page);
  await expect(nav.getByRole('link', { name: 'Chat', exact: true }), 'the header navigation holds Chat').toBeVisible();
  await expect(page.getByRole('link', { name: 'Settings', exact: true }), 'and no Settings link').toHaveCount(0);

  await page.evaluate(() => {
    location.hash = '#/settings';
  });
  await expect(page.getByText(DENIED, { exact: true }), 'the address shows the denied text').toBeVisible();
  await expect(page, 'the page is still titled Settings').toHaveTitle('Settings \u00B7 OcuTalon');
  await expect(sectionsNav(page), 'with no sections').toHaveCount(0);
  const back = page.getByRole('link', { name: 'Back to the chat', exact: true });
  await expect(back, 'and a link back to the chat').toBeVisible();
  await back.click();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');

  const wanted = { error: { code: 'not_admin', message: DENIED } };
  const got = await page.request.get(SETTINGS);
  expect(got.status(), 'GET /v1/settings is 403').toBe(403);
  expect(await got.json(), 'in the error shape').toEqual(wanted);
  for (const slug of SECTIONS) {
    const answer = await page.request.post(`${SETTINGS}/${slug}`, { headers: envelope(), data: {} });
    expect(answer.status(), `POST /v1/settings/${slug} is 403`).toBe(403);
    expect(await answer.json(), `${slug}: not_admin`).toEqual(wanted);
  }
  const sendNow = await page.request.post(`${SETTINGS}/daily-digest/send`, { headers: envelope(), data: {} });
  expect(sendNow.status(), 'POST /v1/settings/daily-digest/send is 403').toBe(403);
  expect(await sendNow.json(), 'send: not_admin').toEqual(wanted);
  const noEnvelope = await page.request.post(`${SETTINGS}/check-thresholds`, { data: {} });
  expect(noEnvelope.status(), 'the admin check comes before the envelope check').toBe(403);
  expect(((await noEnvelope.json()) as { error: { code: string } }).error.code).toBe('not_admin');
});

/**
 * S15 (Story 35.2): a real sign-in over HTTP through the product's own sign-in page records whether the user held OcuTalonAdmin
 * (OnLogin passes Admin.Held($Roles) to AttachFor): the README account (an admin) leaves AdminAtSignIn 1 and its Ref in
 * Ownership.AdminSessions(); the live fixture user (OcuTalonUser only) leaves 0 and its Ref out. Each flag is first written to the
 * opposite value, and an attach that leaves the flag alone would keep it, so only OnLogin's argument can make the test pass. The
 * settings route answers the same two accounts through the same whole-name check: 200 and 403 not_admin.
 */
test('S15: a sign-in records OcuTalonAdmin held at sign-in, and only for an admin', async ({ playwright }) => {
  const live = fixtureUser('LIVE');
  const accounts = [
    { who: 'the README account (OcuTalonAdmin)', ...README_ACCOUNT, before: 0 as const, flag: '1', listed: true, status: 200 },
    { who: 'the live fixture user (OcuTalonUser only)', user: live.user, password: live.password, before: 1 as const, flag: '0', listed: false, status: 403 },
  ];
  for (const account of accounts) {
    const seeded = await adminAtSignIn(account.user, account.before);
    const api = await playwright.request.newContext({ baseURL: process.env['OCUTALON_URL'] });
    try {
      await signInOverHttp(api, account.user, account.password);
      const settings = await api.get(SETTINGS);
      expect(settings.status(), `${account.who}: GET /v1/settings after the sign-in`).toBe(account.status);
      if (account.status === 403) expect(await settings.json(), 'not_admin').toEqual({ error: { code: 'not_admin', message: DENIED } });
    } finally {
      await api.dispose();
    }
    const read = await adminAtSignIn(account.user);
    expect(read.ref, `${account.who}: the same session row`).toBe(seeded.ref);
    expect(read.flag, `${account.who}: AdminAtSignIn after the sign-in`).toBe(account.flag);
    expect(read.listed, `${account.who}: its Ref ${account.listed ? 'is' : 'is not'} in Ownership.AdminSessions()`).toBe(account.listed);
  }
});

/** The state of the instance as the settings page's session sees it: the stored zone, the digest values, and whether demo mode is on. */
async function instanceValues(page: Page): Promise<{ zone: string; time: string; channels: string; demo: boolean }> {
  const response = await page.request.get(SETTINGS);
  expect(response.status(), 'GET /v1/settings as an admin').toBe(200);
  const body = (await response.json()) as {
    sections: { 'daily-digest': { time: string; channels: string }; 'demo-mode': { demoMode: boolean } };
    bridge: Record<string, string | number>;
  };
  const zone = body.bridge['InstanceZone'];
  return { zone: typeof zone === 'string' ? zone : '', time: body.sections['daily-digest'].time, channels: body.sections['daily-digest'].channels, demo: body.sections['demo-mode'].demoMode };
}

/** Opens a section of the settings page for the README admin. */
async function openSection(page: Page, label: string): Promise<void> {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: label, exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: label })).toBeVisible();
}

/** S9: the Time zone section saves a zone, shows the saved text, and GET /v1/settings returns the zone; the test puts the zone back. */
test('S9: saving a time zone shows the saved text, and GET /v1/settings returns the zone', async ({ page }) => {
  await recordAnnouncements(page);
  await openSection(page, 'Time zone');
  const before = await instanceValues(page);
  // The role keeps the locator on the select: the section region carries the same name.
  const select = page.getByRole('combobox', { name: 'Time zone', exact: true });
  await expect(select, 'the select is preselected from the stored zone').toHaveValue(before.zone);
  await expect(select.locator('option').first(), 'the first choice is the Server default').toHaveText('Server default');
  await expect(page.getByText("Message times, reminders, the daily digest and the current time that OcuTalon gives the model use this zone. Times on this page stay in your browser's zone.")).toBeVisible();
  const zone = before.zone === 'Asia/Tokyo' ? 'Europe/Berlin' : 'Asia/Tokyo';
  try {
    await select.selectOption(zone);
    await saveButton(page).click();
    await expect(savedText(page), 'the saved text shows').toBeVisible();
    await expect.poll(() => announcements(page, SAVED), 'and is announced').toBe(1);
    expect((await instanceValues(page)).zone, 'GET shows the new zone at once').toBe(zone);
    await page.reload();
    await sectionsNav(page).getByRole('link', { name: 'Time zone', exact: true }).click();
    await expect(page.getByRole('combobox', { name: 'Time zone', exact: true }), 'a reload shows the saved zone').toHaveValue(zone);
  } finally {
    const put = await page.request.post(`${SETTINGS}/time-zone`, { headers: envelope(), data: { InstanceZone: before.zone } });
    expect(put.status(), 'the zone is put back').toBe(200);
  }
  expect((await instanceValues(page)).zone, 'and GET shows it').toBe(before.zone);
});

/** S10: the Daily digest section shows the channel boxes that the stack's demo mode allows, saves the time and the channels, and keeps a hidden channel as stored. */
test('S10: the Daily digest section saves the time and the channels, and keeps a hidden channel', async ({ page }) => {
  await recordAnnouncements(page);
  await openSection(page, 'Daily digest');
  const before = await instanceValues(page);
  const time = page.getByLabel('Send at', { exact: true });
  const web = page.getByRole('checkbox', { name: 'The web chat', exact: true });
  const phone = page.getByRole('checkbox', { name: 'The simulated phone', exact: true });
  await expect(time, 'the time shows the stored value').toHaveValue(before.time);
  await expect(page.getByText("In the instance's time zone. Applies from the next digest.")).toBeVisible();
  await expect(web, 'the web chat box always shows').toBeVisible();
  await expect(phone, 'the simulated phone box shows only while demo mode is on').toHaveCount(before.demo ? 1 : 0);
  const stored = before.channels.split(',').map((name) => name.trim().toLowerCase());
  await expect(web, 'and is checked as stored').toBeChecked({ checked: stored.includes('web') });
  const newTime = before.time === '06:45' ? '06:46' : '06:45';
  try {
    await time.fill(newTime);
    await web.check();
    await saveButton(page).click();
    await expect(savedText(page), 'the saved text shows').toBeVisible();
    await expect.poll(() => announcements(page, SAVED), 'and is announced').toBe(1);
    const after = await instanceValues(page);
    expect(after.time, 'GET shows the new time').toBe(newTime);
    const saved = after.channels.split(',');
    expect(saved.includes('web'), 'web is saved').toBe(true);
    expect(saved.includes('phone'), 'the phone channel is as it was whether or not its box shows').toBe(stored.includes('phone'));
    expect(after.channels, 'the channels are in the order web, phone, telegram').toBe(['web', 'phone', 'telegram'].filter((name) => saved.includes(name)).join(','));
  } finally {
    const put = await page.request.post(`${SETTINGS}/daily-digest`, { headers: envelope(), data: { time: before.time, channels: before.channels } });
    expect(put.status(), 'the digest values are put back').toBe(200);
  }
  const restored = await instanceValues(page);
  expect(restored.time, 'the time is back').toBe(before.time);
  expect(restored.channels, 'and so are the channels').toBe(before.channels);
});

/** S11: Send my digest now follows the busy pattern and then shows the confirmation (the answer is stubbed, so no digest is made); a failed send shows the failure text. */
test('S11: Send my digest now is busy, then shows the confirmation, and a failed send shows the failure', async ({ page }) => {
  await recordAnnouncements(page);
  await openSection(page, 'Daily digest');
  const send = page.getByRole('button', { name: 'Send my digest now', exact: true });
  await expect(send).toBeVisible();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const posts: string[] = [];
  await page.route('**/api/v1/settings/daily-digest/send', async (route) => {
    posts.push(route.request().method());
    await gate;
    await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ result: 'sending' }) });
  });
  try {
    await send.click();
    await expect(send, 'the button is busy').toHaveAttribute('aria-busy', 'true');
    await expect(send, 'and aria-disabled, never disabled').toHaveAttribute('aria-disabled', 'true');
    await send.click({ force: true });
    release();
    await expect(page.getByText('Sending your digest now.', { exact: true }).first(), 'the confirmation shows').toBeVisible();
    await expect(send, 'and the button is restored').not.toHaveAttribute('aria-busy', 'true');
    await expect.poll(() => announcements(page, 'Sending your digest now.'), 'the confirmation is announced').toBe(1);
    expect(posts, 'one POST was made while the button was busy').toEqual(['POST']);
  } finally {
    release();
    await page.unroute('**/api/v1/settings/daily-digest/send');
  }
  await page.route('**/api/v1/settings/daily-digest/send', (route) =>
    route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) }),
  );
  try {
    await send.click();
    await expect(page.locator('#digest-send-result'), 'a failed send shows the failure text').toHaveText("Couldn't send your digest. Try again.");
    await expect(send, 'and the button is restored').not.toHaveAttribute('aria-busy', 'true');
  } finally {
    await page.unroute('**/api/v1/settings/daily-digest/send');
  }
});

/** S12: the Channels section shows the Telegram state that /v1/state holds and nothing to edit in it: no button, no field, no token (the Email group below it has its own form, Story 21.2). */
test('S12: the Channels section shows the state of Telegram, read only', async ({ page }) => {
  await openSection(page, 'Channels');
  const state = (await (await page.request.get('/ocutalon/api/v1/state')).json()) as { telegram: { included: boolean; state: string }; status: { condition?: string; active?: boolean }[] };
  const telegram = state.telegram;
  const pausedNow = state.status.some((one) => one.condition === 'telegramPaused' && one.active === true);
  await expect(page.getByText("This part of OcuTalon isn't built yet."), 'the section is built').toHaveCount(0);
  const telegramBlock = page.locator('.telegram');
  await expect(telegramBlock.getByRole('textbox'), 'the Telegram block has no field, so no token can be entered').toHaveCount(0);
  await expect(telegramBlock.getByRole('button'), 'and no button').toHaveCount(0);
  await expect(page.locator('app-email-section').getByRole('textbox'), 'the Email group\'s fields are its address, two servers, user name and password (Stories 21.2 and 21.6)').toHaveCount(5);
  const hookFields = await page.locator('app-webhooks-section').getByRole('textbox').count();
  expect(hookFields, 'the Webhooks group has at least its Name and Secret fields (Story 35.3)').toBeGreaterThanOrEqual(2);
  await expect(page.getByRole('textbox'), 'and the section has no other field').toHaveCount(5 + hookFields);
  const notSetUp = page.getByText('Telegram not set up', { exact: true });
  const paused = page.getByText('Telegram paused', { exact: true });
  const on = page.getByText('Telegram on', { exact: true });
  if (!telegram.included) {
    await expect(notSetUp.or(paused).or(on), 'a release without Telegram shows no Telegram block').toHaveCount(0);
  } else if (pausedNow) {
    await expect(paused, 'a paused bot shows the paused text').toBeVisible();
    await expect(page.getByText(/^Trying again at /), 'and when it tries again').toBeVisible();
  } else if (telegram.state === 'off' || telegram.state === 'rejected') {
    await expect(notSetUp, 'a bot that is not set up shows that').toBeVisible();
    const link = page.getByRole('link', { name: 'How to set it up' });
    await expect(link, 'with the guide link').toHaveAttribute('href', /\/GUIDE\.md#telegram$/);
    await expect(link, 'that opens in a new tab').toHaveAttribute('target', '_blank');
  } else {
    await expect(on, 'a bot that is on shows that').toBeVisible();
  }
});

const MODEL_ROUTE = `${SETTINGS}/models`;
const MODELS_URL = '**/api/v1/settings/models';
const MODEL_AGENTS = [
  ['Triage agent', 'TriageAgent'],
  ['Diagnosis agent', 'DiagnosisAgent'],
  ['Chat agent', 'ChatAgent'],
] as const;

interface ProviderRowBody {
  provider: string;
  keyVariable: string;
  keySet: boolean;
  supported: boolean;
}
interface ModelsBody {
  providers: ProviderRowBody[];
  bridge: { agents: Record<string, { provider: string; model: string; secondProvider: string; secondModel: string }>; DecisionTokenBudget: string; DailyCostCapUSD: string };
  prices: Record<string, { input: number; output: number; cacheRead: number; cacheWrite: number }>;
}

/** The whole GET /v1/settings body, as the models and budgets sections read it. */
async function modelValues(page: Page): Promise<ModelsBody> {
  const response = await page.request.get(SETTINGS);
  expect(response.status(), 'GET /v1/settings as an admin').toBe(200);
  return (await response.json()) as ModelsBody;
}

/** Puts the agents and prices of the body back through the API, with the envelope of a state-changing call. */
async function restoreModels(page: Page, before: ModelsBody): Promise<void> {
  const response = await page.request.post(MODEL_ROUTE, { headers: envelope(), data: { agents: before.bridge.agents, prices: before.prices } });
  expect(response.status(), 'the models and prices are restored').toBe(200);
}

/** An agent's group on the Models section, named by its legend. */
const agentGroup = (page: Page, label: string): Locator => page.getByRole('group', { name: label, exact: true });
/** The prices of one model: the group of the model inside the Prices group. */
const priceGroup = (page: Page, model: string): Locator => page.getByRole('group', { name: 'Prices', exact: true }).getByRole('group', { name: model, exact: true });

/**
 * S13 (Story 18.3; AC 1, AC 2): the Models section lists each agent with its provider, model and second model. Only the supported provider is listed; a provider whose key is
 * not set is aria-disabled, described by "No key set. Add {variable} to .env.", and its models cannot be chosen. The page holds no key-shaped text. Test on a stack with no
 * key shows "Didn't answer: no model key is set"; a stubbed answer shows "Answered in 1.2 s"; a price save shows the saved text, GET returns the price and the test puts it back.
 */
test('S13: the Models section lists the supported provider, tests a model and saves a price', async ({ page }) => {
  await recordAnnouncements(page);
  await openSection(page, 'Models');
  const before = await modelValues(page);
  const supported = before.providers.filter((row) => row.supported);
  expect(supported.length, 'control: the stack has a supported provider').toBeGreaterThan(0);
  const anthropic = supported.find((row) => row.provider === 'anthropic');
  expect(anthropic, 'and it is Anthropic').toBeDefined();
  expect(anthropic?.keySet, 'control: a CI stack holds no model key').toBe(false);
  expect(JSON.stringify(before), 'GET /v1/settings holds no key value').not.toMatch(/sk-[A-Za-z0-9_-]{8,}|AIza[0-9A-Za-z_-]{10,}/);

  for (const [label, name] of MODEL_AGENTS) {
    const group = agentGroup(page, label);
    await expect(group, `${label} has its group`).toHaveCount(1);
    await expect(group.getByRole('radio'), `${label} lists the supported provider only`).toHaveCount(supported.length);
    const radio = group.getByRole('radio', { name: 'Anthropic', exact: true });
    await expect(radio, `${label}: Anthropic is the agent's provider`).toBeChecked({ checked: before.bridge.agents[name]?.provider === 'anthropic' });
    await expect(radio, `${label}: a provider without a key is aria-disabled`).toHaveAttribute('aria-disabled', 'true');
    await expect(radio, `${label}: described by the reason`).toHaveAccessibleDescription('No key set. Add ANTHROPIC_API_KEY to .env.');
    await radio.focus();
    await expect(radio, `${label}: and focusable`).toBeFocused();
    await expect(group.getByLabel('Model', { exact: true }).getByRole('option', { name: 'claude-sonnet-5-5', exact: true }), `${label}: its models cannot be chosen`).toBeDisabled();
    await expect(group.getByLabel('Second model', { exact: true }), `${label} has the Second model select`).toBeVisible();
    await expect(group.getByRole('button', { name: 'Test', exact: true }), `${label} has its Test button`).toBeVisible();
  }
  await expect(page.getByRole('radio', { name: /^(?!Anthropic$)/ }), 'no other provider is listed').toHaveCount(0);
  await expect(page.getByText("A change applies from the agent's next model request.")).toBeVisible();
  await expect(page.getByText("Test sends one short request to the agent's saved model.").first()).toBeVisible();
  const page_text = (await page.locator('main').innerText()) ?? '';
  expect(page_text, 'the page holds no key-shaped text').not.toMatch(/sk-[A-Za-z0-9_-]{8,}|AIza[0-9A-Za-z_-]{10,}/);

  // A real Test on a stack with no model key.
  const triage = agentGroup(page, 'Triage agent');
  await triage.getByRole('button', { name: 'Test', exact: true }).click();
  await expect(triage.getByText("Didn't answer: no model key is set", { exact: true }), 'a stack with no key says so').toBeVisible({ timeout: 30_000 });
  await expect.poll(() => announcements(page, "Didn't answer: no model key is set"), 'and the announcer reads it').toBe(1);

  // A stubbed answer: the busy pattern while the call is out, then the seconds with one decimal.
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  await page.route('**/api/v1/settings/models/test', async (route) => {
    await gate;
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ answered: true, seconds: 1.2, reason: '' }) });
  });
  try {
    const diagnosis = agentGroup(page, 'Diagnosis agent');
    const test = diagnosis.getByRole('button', { name: 'Test', exact: true });
    await test.click();
    await expect(test, 'the button is busy').toHaveAttribute('aria-busy', 'true');
    release();
    await expect(diagnosis.getByText('Answered in 1.2 s', { exact: true }), 'and the line reads the seconds').toBeVisible();
    await expect(test, 'then the button is restored').not.toHaveAttribute('aria-busy', 'true');
  } finally {
    release();
    await page.unroute('**/api/v1/settings/models/test');
  }

  // A price save, read back by GET and put back.
  const model = Object.keys(before.prices)[0];
  expect(model, 'control: the stack has a priced model').toBeDefined();
  if (model === undefined) return;
  const input = priceGroup(page, model).getByLabel('Input', { exact: true });
  await expect(input, 'the price shows the stored value').toHaveValue(String(before.prices[model]!.input));
  const next = before.prices[model]!.input + 1;
  try {
    await input.fill(String(next));
    await saveButton(page).click();
    await expect(savedText(page), 'the saved text shows').toBeVisible();
    await expect.poll(() => announcements(page, SAVED), 'and is announced').toBe(1);
    expect((await modelValues(page)).prices[model]!.input, 'GET shows the new price').toBe(next);
    await page.reload();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Settings');
    await expect(priceGroup(page, model).getByLabel('Input', { exact: true }), 'a reload shows the saved price').toHaveValue(String(next));
  } finally {
    await restoreModels(page, before);
  }
  expect((await modelValues(page)).prices[model]!.input, 'the price is back').toBe(before.prices[model]!.input);
});

/**
 * S13c (Story 18.3; AC 1, AC 3, DW-948): on a page whose GET /v1/settings reports a key for Anthropic, choosing Triage's model and a second model posts exactly those
 * changes and leaves the other agents as loaded; a save that changes the model clears the Test line that described the old one; a refusal that names TriageAgent marks the
 * Model select, and one that names TriageAgent.second marks the Second model select, each focused. The server answers are stubs: nothing is written.
 */
test('S13c: choosing a model and a second model posts them, a save clears the Test line, and a refusal marks the named select', async ({ page }) => {
  await page.route('**/api/v1/settings', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    const response = await route.fetch();
    const body = (await response.json()) as ModelsBody;
    for (const row of body.providers) {
      if (row.provider === 'anthropic') row.keySet = true;
    }
    await route.fulfill({ status: response.status(), contentType: 'application/json', body: JSON.stringify(body) });
  });
  await page.route('**/api/v1/settings/models/test', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ answered: true, seconds: 1.2, reason: '' }) }),
  );
  const posted: { agents: Record<string, { provider: string; model: string; secondProvider: string; secondModel: string }> }[] = [];
  let refusal: string[] = [];
  await page.route(MODELS_URL, async (route) => {
    if (route.request().method() !== 'POST') {
      await route.continue();
      return;
    }
    posted.push(route.request().postDataJSON());
    if (refusal.length > 0) {
      await route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ error: { code: 'bad_settings', message: FAILED }, fields: refusal }) });
    } else {
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ outcome: 'done' }) });
    }
  });
  try {
    await openSection(page, 'Models');
    const before = await modelValues(page);
    const triage = agentGroup(page, 'Triage agent');
    const model = triage.getByLabel('Model', { exact: true });
    const second = triage.getByLabel('Second model', { exact: true });
    await expect(triage.getByRole('radio', { name: 'Anthropic', exact: true }), 'a provider with a key can be chosen').not.toHaveAttribute('aria-disabled', 'true');
    await triage.getByRole('button', { name: 'Test', exact: true }).click();
    await expect(triage.getByText('Answered in 1.2 s', { exact: true }), 'the Test line shows').toBeVisible();

    await model.selectOption('claude-sonnet-5-5');
    await second.selectOption('anthropic/claude-sonnet-5-5');
    await saveButton(page).click();
    await expect(savedText(page), 'the saved text shows').toBeVisible();
    expect(posted.length, 'one save was posted').toBe(1);
    expect(posted[0]!.agents['TriageAgent'], 'the chosen model and second model are posted').toEqual({
      provider: 'anthropic',
      model: 'claude-sonnet-5-5',
      secondProvider: 'anthropic',
      secondModel: 'claude-sonnet-5-5',
    });
    expect(posted[0]!.agents['DiagnosisAgent']?.model, 'the other agents are as loaded').toBe(before.bridge.agents['DiagnosisAgent']?.model);
    await expect(triage.getByText('Answered in 1.2 s', { exact: true }), 'a save that changes the model clears the Test line').toHaveCount(0);

    refusal = ['TriageAgent'];
    await model.selectOption('claude-haiku-5-5');
    await saveButton(page).click();
    await expect(model, 'a refusal that names TriageAgent marks the Model select').toHaveAttribute('aria-invalid', 'true');
    await expect(model, 'which is focused').toBeFocused();
    await expect(second, 'and not the Second model select').not.toHaveAttribute('aria-invalid', 'true');

    refusal = ['TriageAgent.second'];
    await second.selectOption('');
    await saveButton(page).click();
    await expect(second, 'a refusal that names TriageAgent.second marks the Second model select').toHaveAttribute('aria-invalid', 'true');
    await expect(second, 'which is focused').toBeFocused();
    await expect(model, 'and not the Model select').not.toHaveAttribute('aria-invalid', 'true');
  } finally {
    await page.unroute(MODELS_URL);
    await page.unroute('**/api/v1/settings/models/test');
    await page.unroute('**/api/v1/settings');
  }
});

/** S13b (Story 18.3; DW-948): a refusal that names a price group shows the field error on that group; a refusal that names nothing the page knows shows the form error. */
test('S13b: a refused save shows the field error on the named price, and a refusal that names nothing shows the form error', async ({ page }) => {
  await openSection(page, 'Models');
  const before = await modelValues(page);
  const model = Object.keys(before.prices)[0];
  expect(model, 'control: the stack has a priced model').toBeDefined();
  if (model === undefined) return;
  const stub = (fields: string[]) => (route: Route) =>
    route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ error: { code: 'bad_settings', message: FAILED }, fields }) });
  const group = priceGroup(page, model);
  const input = group.getByLabel('Input', { exact: true });
  try {
    await page.route(`${MODELS_URL}`, stub([`prices.${model}`]));
    await input.fill(String(before.prices[model]!.input + 1));
    await saveButton(page).click();
    await expect(group.getByText(FAILED, { exact: true }), 'the named price group shows the field error').toBeVisible();
    await expect(input, 'its fields are marked invalid').toHaveAttribute('aria-invalid', 'true');
    await expect(input, 'the first field of the group takes focus').toBeFocused();
    await input.fill(String(before.prices[model]!.input + 2));
    await expect(group.getByText(FAILED, { exact: true }), 'typing clears the error').toHaveCount(0);
    await page.unroute(`${MODELS_URL}`);
    await page.route(`${MODELS_URL}`, stub(['zz-unknown']));
    await saveButton(page).click();
    await expect(page.locator('p.field-error').filter({ hasText: FAILED }), 'a refusal that names nothing the page knows shows the form error once').toHaveCount(1);
    await expect(group.getByText(FAILED, { exact: true }), 'not under a price group').toHaveCount(0);
  } finally {
    await page.unroute(`${MODELS_URL}`);
  }
  expect((await modelValues(page)).prices[model]!.input, 'nothing was written').toBe(before.prices[model]!.input);
});

/**
 * S14 (Story 18.3; AC 4): the Budgets section shows the two stored values with their help lines, saves a token budget and a daily cap, shows the saved text, and GET returns
 * them; a refused value shows the field error on that field, focused; the test puts the values back.
 */
test('S14: the Budgets section saves a token budget and a cap, and a refused value shows the field error', async ({ page }) => {
  await recordAnnouncements(page);
  await openSection(page, 'Budgets');
  const before = await modelValues(page);
  const tokens = page.getByLabel('Token budget per decision', { exact: true });
  const cap = page.getByLabel('Daily cost cap (US dollars)', { exact: true });
  await expect(tokens, 'the token budget shows the stored value').toHaveValue(String(before.bridge.DecisionTokenBudget));
  await expect(cap, 'and so does the cap').toHaveValue(String(before.bridge.DailyCostCapUSD));
  await expect(tokens, 'the token budget is described by its help line').toHaveAccessibleDescription('A decision that would use more tokens than this uses fixed rules instead. 0 is off.');
  await expect(cap, 'and so is the cap').toHaveAccessibleDescription("When today's model cost reaches the cap, decisions use fixed rules until midnight in the instance's time zone. 0 is off.");
  const restoreBudgets = async (): Promise<void> => {
    const put = await page.request.post(`${SETTINGS}/budgets`, { headers: envelope(), data: { DecisionTokenBudget: before.bridge.DecisionTokenBudget, DailyCostCapUSD: before.bridge.DailyCostCapUSD } });
    expect(put.status(), 'the budgets are put back').toBe(200);
  };
  const newTokens = before.bridge.DecisionTokenBudget === '9000' ? '9100' : '9000';
  const newCap = before.bridge.DailyCostCapUSD === '7.5' ? '7.6' : '7.5';
  try {
    await tokens.fill(newTokens);
    await cap.fill(newCap);
    await saveButton(page).click();
    await expect(savedText(page), 'the saved text shows').toBeVisible();
    await expect.poll(() => announcements(page, SAVED), 'and is announced').toBe(1);
    const after = await modelValues(page);
    expect(after.bridge.DecisionTokenBudget, 'GET shows the new token budget').toBe(newTokens);
    expect(after.bridge.DailyCostCapUSD, 'and the new cap').toBe(newCap);

    await cap.fill('7.555');
    await saveButton(page).click();
    await expect(page.locator('#budget-cap-error'), 'a cap of three decimals shows the field error').toHaveText(FAILED);
    await expect(cap, 'the field is marked invalid').toHaveAttribute('aria-invalid', 'true');
    await expect(cap, 'and focused').toBeFocused();
    await expect(page.locator('#budget-tokens-error'), 'the other field has none').toHaveCount(0);
    expect((await modelValues(page)).bridge.DailyCostCapUSD, 'nothing was written').toBe(newCap);
    await tokens.fill('abc');
    await cap.fill(newCap);
    await saveButton(page).click();
    await expect(page.locator('#budget-tokens-error'), 'a token budget that is not a number shows the field error').toHaveText(FAILED);
    await expect(tokens, 'focused').toBeFocused();
  } finally {
    await restoreBudgets();
  }
  const restored = await modelValues(page);
  expect(restored.bridge.DecisionTokenBudget, 'the token budget is back').toBe(before.bridge.DecisionTokenBudget);
  expect(restored.bridge.DailyCostCapUSD, 'and so is the cap').toBe(before.bridge.DailyCostCapUSD);
});
