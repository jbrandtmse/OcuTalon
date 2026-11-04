import { expect, test, type Locator, type Page } from '@playwright/test';

import { envelope, signIn } from '../sign-in/helpers';
import { loadedAfter, signInReadmeLoaded } from '../support/floor';
import { fixtureUser } from '../support/iris';

/**
 * Story 33.2, the settings page for an admin (S1 to S8, with S1t and S7b), in a real browser against a real stack: the README account holds OcuTalonAdmin, and the live
 * fixture user (OCUTALON_LIVE_USER, test-sign-in.sh) holds OcuTalonUser only. The cases that save restore the five thresholds they change.
 */
const SETTINGS = '/ocutalon/api/v1/settings';
const SECTIONS = ['check-thresholds', 'budgets', 'models', 'channels', 'daily-digest', 'time-zone', 'demo-mode'] as const;
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
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

/** S1: the header navigation, the title and the seven sections in the UX's order. */
test('S1: an admin sees Chat and Settings in the header, and Settings opens the page with its seven sections', async ({ page }) => {
  await signInReadmeLoaded(page);
  const guide = page.getByRole('region', { name: 'Demo guide' });
  await expect(guide, 'the main page has the demo guide (demo mode on)').toHaveCount(1);
  const nav = pagesNav(page);
  await expect(nav, 'the header holds one navigation landmark named Pages').toHaveCount(1);
  await expect(nav.getByRole('link'), 'with Chat and Settings').toHaveText(['Chat', 'Settings']);
  await expect(nav.getByRole('link', { name: 'Chat', exact: true }), 'the current page is marked').toHaveAttribute('aria-current', 'page');
  await expect(nav.getByRole('link', { name: 'Settings', exact: true })).not.toHaveAttribute('aria-current', 'page');

  await nav.getByRole('link', { name: 'Settings', exact: true }).click();
  expect(new URL(page.url()).hash, 'at the address #/settings').toBe('#/settings');
  await expect(nav.getByRole('link', { name: 'Settings', exact: true }), 'Settings is now the current page').toHaveAttribute('aria-current', 'page');
  await expect(nav.getByRole('link', { name: 'Chat', exact: true })).not.toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('heading', { level: 1 }), 'one h1').toHaveText('Settings');
  await expect(sectionsNav(page).getByRole('link'), 'the sections, in the UX order').toHaveText(['Models', 'Budgets', 'Channels', 'Daily digest', 'Time zone', 'Check thresholds', 'Demo mode']);
  await expect(page.getByRole('heading', { level: 2 }), '#/settings opens Models').toHaveText('Models');
  await expect(page.getByText("This part of OcuTalon isn't built yet.")).toBeVisible();
  await expect(page.getByRole('button', { name: 'Save changes' }), 'a section that is not built has no button').toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Skip to chat', exact: true }), 'the skip links belong to the main page').toHaveCount(0);
  await expect(guide, 'and so does the demo guide').toHaveCount(0);

  for (const [slug, label] of [['budgets', 'Budgets'], ['daily-digest', 'Daily digest'], ['time-zone', 'Time zone']] as const) {
    await sectionsNav(page).getByRole('link', { name: label, exact: true }).click();
    expect(new URL(page.url()).hash, `${label} has its own address`).toBe(`#/settings/${slug}`);
    await expect(sectionsNav(page).getByRole('link', { name: label, exact: true })).toHaveAttribute('aria-current', 'true');
    await expect(page.getByRole('heading', { level: 2 })).toHaveText(label);
    await expect(page.getByText("This part of OcuTalon isn't built yet.")).toBeVisible();
  }
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

/** S2: a save of two thresholds is written, shown, announced and read back by GET /v1/settings. */
test('S2: saving two thresholds shows the saved text, and GET /v1/settings returns the new values', async ({ page }) => {
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
  expect((await thresholds(page)).diskFreePercent, 'nothing changed').toBe(before.diskFreePercent);
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
  expect((await page.request.get(SETTINGS).then((response) => response.json())).sections['demo-mode'].demoMode, 'demo mode is as it was').toBe(was);
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

/** S8: a user without OcuTalonAdmin sees no Settings link, the denied view at #/settings, and 403 not_admin on all eight settings calls. */
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
  const noEnvelope = await page.request.post(`${SETTINGS}/check-thresholds`, { data: {} });
  expect(noEnvelope.status(), 'the admin check comes before the envelope check').toBe(403);
  expect(((await noEnvelope.json()) as { error: { code: string } }).error.code).toBe('not_admin');
});
