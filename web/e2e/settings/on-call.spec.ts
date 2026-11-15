import { expect, test, type Locator, type Page } from '../support/fixtures';

import { README_ACCOUNT, envelope } from '../sign-in/helpers';
import { readmeSession } from '../support/demo-path';
import { signInReadmeLoaded } from '../support/floor';
import { cleanFixtureRows, seedOtherSession } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';
import { ON_CALL_API, ON_CALL_KEYS, auditMark, auditSince, readOnCall, resetOnCall, restoreOnCall, type OnCallStored } from '../support/on-call';

/**
 * Story 36.4, the On call section of Settings in a real browser, signed in as the README admin (O1 to O16; the sign-in-2 unit). The README account holds
 * OcuTalonAdmin, and has a session, so it is one of the OcuTalon users that the section lists. The cases run one after the other, because the on-call values are
 * the instance's own: each case starts from Nobody for both roles with 15 minutes (beforeEach, through the route), and puts back the values it found (afterEach).
 *   O1  the nav link, the heading, the help and the not-yet line, the two legends, a labelled control for every field, the Telegram box disabled with its text,
 *       the line under the on-call person who is by email, and the keyboard order;
 *   O2  the README admin as the on-call person (unpaired: Telegram disabled) and a backup by email with 20 minutes: the saved text, GET and the audit entries
 *       (the admin's user and session, the web channel) match;
 *   O3  a bad address, no channel and 0 minutes mark their fields, focus the first in the form's order and change nothing; fixing them and saving again gives the
 *       new values and only the new audit entries;
 *   O4  the unsaved prompt: Stay keeps the typed value, Leave discards it;
 *   O5  a failed save (a routed 500) shows the failed text under the button;
 *   O6  a GET with no on-call member (the online demo) hides the section and opens Models for its address;
 *   O7  a 409 shows the off-demo text in place of the form, and leaving the page then asks nothing;
 *   O8  a 403 shows the denied view in place of the section;
 *   O9  a user with a paired chat (a routed GET) has Telegram enabled and checked by default, and the saved body carries telegram,email;
 *   O10 an edit made while the save is pending is kept and stays unsaved, and the section opened again shows the saved values (the page keeps them);
 *   O11 a refused user (a routed 400 naming primaryUser) shows its filled text under the Person select, which is marked invalid, described by it and focused;
 *   O12 while the list of users is unavailable (a routed GET with users []), a stored on-call user and backup keep their Telegram and Email boxes, Telegram is
 *       enabled with no unpaired line, and a save that changes only the minutes sends the stored channels;
 *   O13 a stored on-call user who has no session row any more (the real server) has Telegram enabled and the stored Email box, with no unpaired line, and
 *       saving gets the unknown-user text under the Person select, with the stored values and the audit log unchanged;
 *   O14 with the list holding users, a listed user who has not paired has Telegram unchecked and disabled with the one unpaired line, while a stored backup the
 *       list lacks keeps a Telegram-only channel, enabled and with no line, and a save sends Email alone for the first and Telegram alone for the second;
 *   O15 while the list is unavailable and the on-call person is Nobody, a stored backup keeps a Telegram-only channel with Email unchecked, and a save sends it;
 *   O16 a stored backup who has no session row any more (the real server) has Telegram enabled and the stored Email box, and saving gets the unknown-user
 *       text under the backup's Person select, with the stored values and the audit log unchanged.
 * The texts are written out here as the oracle.
 */
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const FAILED = "Couldn't save. Nothing was changed.";
const HELP = 'Choose who OcuTalon pages when an incident starts, and who it pages next if nobody presses Got it in time.';
const NOT_YET = "OcuTalon doesn't send pages yet. It keeps these choices for when it does.";
const BY_EMAIL_HELP = "Someone paged by email can't press Got it, so OcuTalon also pages the backup after the minutes below.";
const BAD_EMAIL = 'Enter an email address such as name@example.com. Nothing was changed.';
const BAD_MINUTES = 'Enter a whole number of minutes from 1 to 1440. Nothing was changed.';
const NO_CHANNEL = 'Choose a way to reach this person: Telegram needs a paired chat, email needs an address. Nothing was changed.';
const EMAIL_ONLY = 'Telegram needs an OcuTalon user with a paired chat.';
const OFF_ON_DEMO = "The online demo has no on-call person, because its visitors aren't admins. On your own install, an admin chooses one here.";
const UNSAVED = 'You have unsaved changes in this section. Leave without saving?';
const DENIED = 'Only OcuTalon admins can open settings.';
const UNKNOWN_USER = (user: string): string => `${user} isn't an OcuTalon user any more. Choose again. Nothing was changed.`;

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });
const saveButton = (page: Page): Locator => page.getByRole('button', { name: 'Save changes', exact: true });
const savedText = (page: Page): Locator => page.locator('p.saved').filter({ hasText: SAVED });
const primary = (page: Page): Locator => page.getByRole('group', { name: 'On-call person', exact: true });
const backup = (page: Page): Locator => page.getByRole('group', { name: 'Backup', exact: true });
const person = (group: Locator): Locator => group.getByLabel('Person', { exact: true });
const address = (group: Locator): Locator => group.getByLabel('Email address for pages', { exact: true });
const pageBy = (group: Locator): Locator => group.getByRole('group', { name: 'Page by', exact: true });
const telegram = (group: Locator): Locator => pageBy(group).getByLabel('Telegram', { exact: true });
const mail = (group: Locator): Locator => pageBy(group).getByLabel('Email', { exact: true });
const minutes = (page: Page): Locator => page.getByLabel('Minutes before paging the backup', { exact: true });

/** The values an earlier run or an operator left, put back after a case. */
let original: OnCallStored | undefined;
/** The values the case starts from: Nobody for both roles, the default channels and 15 minutes. */
let found: OnCallStored | undefined;

test.describe.configure({ mode: 'serial' });

test.beforeEach(async ({ page }) => {
  await recordAnnouncements(page);
  await signInReadmeLoaded(page);
  original = await readOnCall(page.request);
  await resetOnCall(page.request);
  found = await readOnCall(page.request);
});

test.afterEach(async ({ page }) => {
  if (original !== undefined) {
    await restoreOnCall(page.request, original);
  }
});

/** Opens Settings > On call from the header and the sections navigation. */
async function openOnCall(page: Page): Promise<void> {
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'On call', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'On call' })).toBeVisible();
  await expect(minutes(page)).toBeVisible();
}

/** Whether the README admin's Telegram can be chosen: whether one of their sessions has a paired chat. */
const readmePaired = (values: OnCallStored): boolean => values.users.find((one) => one.user === README_ACCOUNT.user)?.paired === true;

/** The entries in the order of their keys, so that two entries written in the same millisecond compare in a fixed order. */
const bySetting = <T extends { setting: string }>(entries: T[]): T[] => [...entries].sort((a, b) => a.setting.localeCompare(b.setting));

/** A tag for the addresses of a case. */
const stamp = (): string => `${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

test('O1: the section has its nav link, heading, help, two labelled groups and a keyboard order, and Telegram is disabled where it cannot be chosen', async ({ page }) => {
  test.setTimeout(180_000);
  await openOnCall(page);
  expect(new URL(page.url()).hash, 'On call has its own address').toBe('#/settings/on-call');
  await expect(sectionsNav(page).getByRole('link', { name: 'On call', exact: true }), 'its link is the current one').toHaveAttribute('aria-current', 'true');
  await expect(page, 'the page keeps its title').toHaveTitle('Settings \u00B7 OcuTalon');
  await expect(page.getByText(HELP, { exact: true }), 'the help line').toBeVisible();
  const pagesBuilt = found?.pagesBuilt === true;
  await expect(page.getByText(NOT_YET, { exact: true }), pagesBuilt ? 'no not-yet line once pages are built' : 'the not-yet line while Data.Page is not compiled').toHaveCount(pagesBuilt ? 0 : 1);
  await expect(primary(page), 'the on-call person group').toBeVisible();
  await expect(backup(page), 'the backup group').toBeVisible();

  for (const group of [primary(page), backup(page)]) {
    await expect(person(group), 'a labelled Person select').toBeVisible();
    const options = await person(group).locator('option').allTextContents();
    expect(options[0], 'Nobody comes first').toBe('Nobody');
    expect(options.at(-1), 'Someone else, by email comes last').toBe('Someone else, by email');
    expect(options, 'the README admin is one of the users').toContain(README_ACCOUNT.user);
    await expect(address(group), 'Nobody has no address field').toHaveCount(0);
    await expect(pageBy(group), 'and no Page by group').toHaveCount(0);
  }
  await expect(minutes(page), 'the minutes field is labelled').toHaveValue(String(found?.escalationMinutes ?? 15));
  await expect(page.getByText('15 unless you change it.', { exact: true }), 'with its help').toBeVisible();
  await expect(minutes(page), 'which describes it').toHaveAccessibleDescription('15 unless you change it.');
  await expect(page.getByText(BY_EMAIL_HELP, { exact: true }), 'no by-email line for Nobody').toHaveCount(0);

  // Someone by email: the address, Page by, Telegram disabled with its text, and the by-email line under the on-call person only.
  await person(primary(page)).selectOption('email');
  await expect(address(primary(page)), 'an address field shows').toBeVisible();
  await expect(pageBy(primary(page)), 'with Page by').toBeVisible();
  await expect(telegram(primary(page)), 'Telegram is disabled for a person by email').toBeDisabled();
  await expect(telegram(primary(page)), 'and described by its text').toHaveAccessibleDescription(EMAIL_ONLY);
  await expect(page.getByText(EMAIL_ONLY, { exact: true })).toBeVisible();
  await expect(mail(primary(page)), 'Email is checked').toBeChecked();
  await expect(page.getByText(BY_EMAIL_HELP, { exact: true }), 'the by-email line shows').toBeVisible();
  await expect(person(primary(page)), 'under the Person select').toHaveAccessibleDescription(BY_EMAIL_HELP);
  await person(backup(page)).selectOption('email');
  await expect(page.getByText(BY_EMAIL_HELP, { exact: true }), 'and only once: the backup has no further escalation').toHaveCount(1);

  // The README admin: Telegram can be chosen only with a paired chat.
  await person(backup(page)).selectOption('nobody');
  await person(primary(page)).selectOption(`user:${README_ACCOUNT.user}`);
  await expect(page.getByText(BY_EMAIL_HELP, { exact: true }), 'a user has no by-email line').toHaveCount(0);
  if (readmePaired(found as OnCallStored)) {
    await expect(telegram(primary(page)), 'a paired user can be paged by Telegram').toBeEnabled();
    await expect(telegram(primary(page)), 'and starts checked').toBeChecked();
  } else {
    await expect(telegram(primary(page)), 'a user without a paired chat has Telegram disabled').toBeDisabled();
    await expect(telegram(primary(page)), 'unchecked').not.toBeChecked();
    await expect(telegram(primary(page)), 'with the filled text').toHaveAccessibleDescription(
      `${README_ACCOUNT.user} hasn't paired Telegram, so OcuTalon can't message them there yet. They can pair it on their own OcuTalon page.`,
    );
  }
  await expect(mail(primary(page)), 'Email starts checked').toBeChecked();

  // The keyboard order: Person, address, the Page by boxes that can be chosen, the backup's Person, the minutes, Save changes.
  await person(primary(page)).focus();
  await page.keyboard.press('Tab');
  await expect(address(primary(page)), 'Tab goes to the address').toBeFocused();
  await page.keyboard.press('Tab');
  if (readmePaired(found as OnCallStored)) {
    await expect(telegram(primary(page)), 'then Telegram').toBeFocused();
    await page.keyboard.press('Tab');
  }
  await expect(mail(primary(page)), 'then Email').toBeFocused();
  await page.keyboard.press('Space');
  await expect(mail(primary(page)), 'Space unchecks it').not.toBeChecked();
  await page.keyboard.press('Space');
  await expect(mail(primary(page)), 'and checks it again').toBeChecked();
  await page.keyboard.press('Tab');
  await expect(person(backup(page)), 'then the backup\'s Person').toBeFocused();
  await page.keyboard.press('Tab');
  await expect(minutes(page), 'then the minutes').toBeFocused();
  await page.keyboard.press('Tab');
  await expect(saveButton(page), 'then Save changes').toBeFocused();
});

test('O2: the README admin as the on-call person and a backup by email are saved, and GET and the audit entries match', async ({ page }) => {
  test.setTimeout(240_000);
  const before = found as OnCallStored;
  const tag = stamp();
  const primaryAddress = `zz-o2p-${tag}@example.com`;
  const backupAddress = `zz-o2b-${tag}@example.com`;
  const mark = await auditMark();
  await openOnCall(page);
  await person(primary(page)).selectOption(`user:${README_ACCOUNT.user}`);
  await address(primary(page)).fill(primaryAddress);
  if (readmePaired(before)) {
    await telegram(primary(page)).uncheck();
  }
  await person(backup(page)).selectOption('email');
  await address(backup(page)).fill(backupAddress);
  await minutes(page).fill('20');
  await saveButton(page).click();
  await expect(savedText(page), 'the saved text shows').toBeVisible();
  await expect.poll(() => announcements(page, SAVED), 'and is announced once').toBe(1);
  await expect(page.getByText(FAILED), 'with no error').toHaveCount(0);

  const after = await readOnCall(page.request);
  expect([after.primaryUser, after.primaryEmail, after.primaryChannels], 'GET shows the on-call person').toEqual([README_ACCOUNT.user, primaryAddress, 'email']);
  expect([after.backupUser, after.backupEmail, after.backupChannels, after.escalationMinutes], 'the backup and the minutes').toEqual(['', backupAddress, 'email', 20]);
  await page.reload();
  await sectionsNav(page).getByRole('link', { name: 'On call', exact: true }).click();
  await expect(address(primary(page)), 'a reload shows the saved address').toHaveValue(primaryAddress);
  await expect(person(backup(page)), 'and the saved kind of person').toHaveValue('email');
  await expect(minutes(page), 'and the saved minutes').toHaveValue('20');

  const wanted = ON_CALL_KEYS.flatMap(([key, member]) => {
    const was = String(before[member]);
    const now = String(after[member]);
    return was === now ? [] : [{ setting: key, from: was, to: now }];
  });
  expect(wanted.length, 'the case changes at least the address and the minutes').toBeGreaterThanOrEqual(3);
  const entries = await auditSince(mark, wanted.length);
  expect(
    bySetting(entries.map((one) => ({ setting: one.setting, from: one.from, to: one.to }))),
    'one audit entry for each changed key, with its value before and now',
  ).toEqual(bySetting(wanted));
  const session = await readmeSession();
  for (const entry of entries) {
    expect([entry.irisUser, entry.sessionRef, entry.channel], `${entry.setting}: the admin's user, the session and the web channel`).toEqual([README_ACCOUNT.user, session.ref, 'web']);
  }
});

test('O3: refused values mark their fields and focus the first, nothing changes, and a correction saves only the new entries', async ({ page }) => {
  test.setTimeout(240_000);
  const before = found as OnCallStored;
  const tag = stamp();
  const good = `zz-o3-${tag}@example.com`;
  const mark = await auditMark();
  await openOnCall(page);
  await person(primary(page)).selectOption('email');
  await address(primary(page)).fill('nope');
  await minutes(page).fill('0');
  await saveButton(page).click();
  await expect(page.locator('#oncall-primary-email-error'), 'the bad address shows its text').toHaveText(BAD_EMAIL);
  await expect(page.locator('#oncall-minutes-error'), 'the bad minutes show theirs').toHaveText(BAD_MINUTES);
  await expect(address(primary(page)), 'the address is marked invalid').toHaveAttribute('aria-invalid', 'true');
  await expect(address(primary(page)), 'and linked to its error').toHaveAttribute('aria-describedby', 'oncall-primary-email-error');
  await expect(minutes(page), 'so are the minutes').toHaveAttribute('aria-invalid', 'true');
  await expect(address(primary(page)), 'the first in the form takes focus').toBeFocused();
  await expect(page.locator('#oncall-error'), 'no form error shows').toHaveCount(0);
  await expect(savedText(page), 'and no saved text').toHaveCount(0);
  expect(await readOnCall(page.request), 'nothing was changed').toEqual(before);
  expect(await auditSince(mark, 0), 'and nothing was audited').toEqual([]);

  // No way to reach the person: Email unchecked for a person by email.
  await address(primary(page)).fill(good);
  await minutes(page).fill('30');
  await mail(primary(page)).uncheck();
  await saveButton(page).click();
  await expect(page.locator('#oncall-primary-channels-error'), 'no channel shows its text').toHaveText(NO_CHANNEL);
  await expect(page.locator('#oncall-primary-email-error'), 'the address error is gone with the address fixed').toHaveCount(0);
  await expect(pageBy(primary(page)), 'Page by is described by it').toHaveAttribute('aria-describedby', 'oncall-primary-channels-error');
  await expect(mail(primary(page)), 'the first box that can be chosen takes focus').toBeFocused();
  expect(await readOnCall(page.request), 'still nothing was changed').toEqual(before);

  // The correction.
  await mail(primary(page)).check();
  await expect(page.locator('#oncall-primary-channels-error'), 'checking a box clears its error').toHaveCount(0);
  await saveButton(page).click();
  await expect(savedText(page), 'the correction is saved').toBeVisible();
  const after = await readOnCall(page.request);
  expect([after.primaryUser, after.primaryEmail, after.primaryChannels, after.escalationMinutes], 'GET shows the new values').toEqual(['', good, 'email', 30]);
  const wanted = ON_CALL_KEYS.flatMap(([key, member]) => (String(before[member]) === String(after[member]) ? [] : [{ setting: key, from: String(before[member]), to: String(after[member]) }]));
  const entries = await auditSince(mark, wanted.length);
  expect(
    bySetting(entries.map((one) => ({ setting: one.setting, from: one.from, to: one.to }))),
    'only the new values are audited: the refused saves wrote nothing',
  ).toEqual(bySetting(wanted));
});

test('O4: unsaved changes ask before a link leaves; Stay keeps the typed value and Leave discards it', async ({ page }) => {
  test.setTimeout(180_000);
  const before = found as OnCallStored;
  await openOnCall(page);
  const typed = before.escalationMinutes === 40 ? '41' : '40';
  await minutes(page).fill(typed);
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog, 'a section link asks first').toBeVisible();
  await expect(dialog).toContainText(UNSAVED);
  await dialog.getByRole('button', { name: 'Stay', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  expect(new URL(page.url()).hash, 'Stay keeps the section').toBe('#/settings/on-call');
  await expect(minutes(page), 'and the typed value').toHaveValue(typed);
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  await dialog.getByRole('button', { name: 'Leave without saving', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2 })).toHaveText('Demo mode');
  await sectionsNav(page).getByRole('link', { name: 'On call', exact: true }).click();
  await expect(minutes(page), 'the discarded value is gone').toHaveValue(String(before.escalationMinutes));
  expect((await readOnCall(page.request)).escalationMinutes, 'and was never saved').toBe(before.escalationMinutes);
  await expect(dialog, 'a clean form asks nothing').toHaveCount(0);
});

test('O5: a failed save shows the failed text under the button', async ({ page }) => {
  test.setTimeout(180_000);
  await openOnCall(page);
  await page.route('**/api/v1/settings/on-call', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.continue();
      return;
    }
    await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } }) });
  });
  const before = found as OnCallStored;
  await minutes(page).fill(before.escalationMinutes === 20 ? '21' : '20');
  await saveButton(page).click();
  await expect(page.locator('#oncall-error'), 'the error is under the button').toHaveText(FAILED);
  await expect(saveButton(page), 'the button is described by it').toHaveAttribute('aria-describedby', 'oncall-error');
  await expect(saveButton(page), 'and is restored').not.toHaveAttribute('aria-busy', 'true');
  await expect(savedText(page), 'no saved text').toHaveCount(0);
});

test('O6: a GET with no on-call member hides the section, and its address opens Models', async ({ page }) => {
  test.setTimeout(180_000);
  await page.route('**/api/v1/settings', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    const response = await route.fetch();
    const body = (await response.json()) as { sections: Record<string, unknown> };
    delete body.sections['on-call'];
    await route.fulfill({ response, json: body });
  });
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await expect(sectionsNav(page).getByRole('link'), 'the navigation has no On call').toHaveText(['Models', 'Budgets', 'Channels', 'Daily digest', 'Time zone', 'Check thresholds', 'Demo mode', 'Tools and MCP servers']);
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2 }), 'Demo mode is open first, so that Models cannot already be showing').toHaveText('Demo mode');
  await page.evaluate(() => {
    location.hash = '#/settings/on-call';
  });
  await expect(page.getByRole('heading', { level: 2 }), 'the address of the hidden section opens Models').toHaveText('Models');
  await expect(sectionsNav(page).getByRole('link', { name: 'Models', exact: true }), 'and Models is the current link').toHaveAttribute('aria-current', 'true');
});

test('O7: a 409 shows the off-demo text in place of the form, and leaving the page then asks nothing', async ({ page }) => {
  test.setTimeout(180_000);
  await page.route('**/api/v1/settings/on-call', async (route) => {
    await route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_available', message: OFF_ON_DEMO } }) });
  });
  await openOnCall(page);
  await minutes(page).fill('44');
  await saveButton(page).click();
  await expect(page.getByText(OFF_ON_DEMO, { exact: true }), 'a 409 shows the off-demo text').toBeVisible();
  await expect(saveButton(page), 'in place of the form').toHaveCount(0);
  await expect(page.getByText(HELP, { exact: true }), 'with no help for the form').toHaveCount(0);
  await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2 }), 'a section link leaves at once').toHaveText('Demo mode');
  await expect(page.getByRole('dialog'), 'with no unsaved-changes prompt for a form that is gone').toHaveCount(0);
});

test('O8: a 403 shows the denied view in place of the section, and nothing is saved', async ({ page }) => {
  test.setTimeout(180_000);
  await page.route('**/api/v1/settings/on-call', async (route) => {
    await route.fulfill({ status: 403, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_admin', message: DENIED } }) });
  });
  await openOnCall(page);
  await minutes(page).fill('44');
  await saveButton(page).click();
  await expect(page.locator('p.denied'), 'the page shows its denied text').toHaveText(DENIED);
  await expect(saveButton(page), 'in place of the form').toHaveCount(0);
  await expect(savedText(page), 'with no saved text').toHaveCount(0);
  expect(await readOnCall(page.request), 'nothing was changed').toEqual(found);
});

test('O9: a user with a paired chat has Telegram enabled and checked, and the saved body carries telegram,email', async ({ page }) => {
  test.setTimeout(180_000);
  await page.route('**/api/v1/settings', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    const response = await route.fetch();
    const body = (await response.json()) as { sections: { 'on-call': OnCallStored } };
    const users = body.sections['on-call'].users.filter((one) => one.user !== README_ACCOUNT.user);
    body.sections['on-call'].users = [...users, { user: README_ACCOUNT.user, paired: true }].sort((a, b) => a.user.localeCompare(b.user));
    await route.fulfill({ response, json: body });
  });
  const posted: unknown[] = [];
  await page.route('**/api/v1/settings/on-call', async (route) => {
    posted.push(route.request().postDataJSON());
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', sections: {} }) });
  });
  await openOnCall(page);
  await person(primary(page)).selectOption(`user:${README_ACCOUNT.user}`);
  await expect(telegram(primary(page)), 'a paired user can be paged by Telegram').toBeEnabled();
  await expect(telegram(primary(page)), 'and starts checked').toBeChecked();
  await expect(mail(primary(page)), 'with Email checked too').toBeChecked();
  await saveButton(page).click();
  await expect(savedText(page), 'the routed save is shown as saved').toBeVisible();
  expect(posted.length, 'one save was posted').toBe(1);
  expect(posted[0], 'its body names the user and both channels').toMatchObject({ primaryPerson: 'user', primaryUser: README_ACCOUNT.user, primaryChannels: 'telegram,email' });
  expect(await readOnCall(page.request), 'nothing was written: the route answered it').toEqual(found);
});

test('O10: an edit made while the save is pending is kept and stays unsaved, and On call opened again shows the saved values', async ({ page }) => {
  test.setTimeout(180_000);
  const before = found as OnCallStored;
  await openOnCall(page);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  await page.route('**/api/v1/settings/on-call', async (route) => {
    if (route.request().method() === 'POST') await gate;
    await route.continue().catch(() => undefined);
  });
  try {
    const sent = before.escalationMinutes === 33 ? '34' : '33';
    const typed = sent === '33' ? '35' : '36';
    await minutes(page).fill(sent);
    await saveButton(page).click();
    await expect(saveButton(page), 'the save is pending').toHaveAttribute('aria-busy', 'true');
    await minutes(page).fill(typed);
    const answered = page.waitForResponse((response) => response.url().endsWith('/v1/settings/on-call') && response.request().method() === 'POST');
    release();
    expect((await answered).status(), 'the save answers').toBe(200);
    await expect(saveButton(page), 'and the button is restored').not.toHaveAttribute('aria-busy', 'true');
    await expect(minutes(page), 'the edit made meanwhile is kept').toHaveValue(typed);
    await expect(savedText(page), 'no saved text shows for a form that is still unsaved').toHaveCount(0);
    expect((await readOnCall(page.request)).escalationMinutes, 'the sent value was saved').toBe(Number(sent));
    await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog, 'the form is still unsaved, so a section link asks first').toBeVisible();
    await dialog.getByRole('button', { name: 'Leave without saving', exact: true }).click();
    await expect(page.getByRole('heading', { level: 2 })).toHaveText('Demo mode');
    await sectionsNav(page).getByRole('link', { name: 'On call', exact: true }).click();
    await expect(minutes(page), 'On call opened again shows the saved value, not the one the page loaded').toHaveValue(sent);
    await sectionsNav(page).getByRole('link', { name: 'Demo mode', exact: true }).click();
    await expect(page.getByRole('heading', { level: 2 }), 'and leaving it asks nothing').toHaveText('Demo mode');
    await expect(dialog).toHaveCount(0);
  } finally {
    release();
    await page.unroute('**/api/v1/settings/on-call');
  }
});

test('O11: a refused user shows its filled text under the Person select, which is marked, described by it and focused', async ({ page }) => {
  test.setTimeout(180_000);
  await openOnCall(page);
  await page.route('**/api/v1/settings/on-call', async (route) => {
    await route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ error: { code: 'bad_settings', message: FAILED }, fields: ['primaryUser'] }) });
  });
  await person(primary(page)).selectOption(`user:${README_ACCOUNT.user}`);
  await address(primary(page)).fill(`zz-o11-${stamp()}@example.com`);
  await saveButton(page).click();
  await expect(page.locator('#oncall-primary-person-error'), 'the filled text names the user').toHaveText(UNKNOWN_USER(README_ACCOUNT.user));
  await expect(person(primary(page)), 'the Person select is marked invalid').toHaveAttribute('aria-invalid', 'true');
  await expect(person(primary(page)), 'and described by its error').toHaveAttribute('aria-describedby', 'oncall-primary-person-error');
  await expect(person(primary(page)), 'and takes focus').toBeFocused();
  await expect(page.locator('#oncall-error'), 'no form error shows').toHaveCount(0);
  await expect(savedText(page), 'and no saved text').toHaveCount(0);
});

test('O12: while the list of users is unavailable, a stored user keeps their channels, and a save that changes only the minutes sends them', async ({ page }) => {
  test.setTimeout(180_000);
  const tag = stamp();
  const gone = `zz-o12-gone-${tag}`;
  await page.route('**/api/v1/settings', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    const response = await route.fetch();
    const body = (await response.json()) as { sections: { 'on-call': OnCallStored } };
    Object.assign(body.sections['on-call'], {
      users: [],
      primaryUser: README_ACCOUNT.user,
      primaryEmail: `zz-o12p-${tag}@example.com`,
      primaryChannels: 'telegram,email',
      backupUser: gone,
      backupEmail: `zz-o12b-${tag}@example.com`,
      backupChannels: 'telegram,email',
    });
    await route.fulfill({ response, json: body });
  });
  const posted: unknown[] = [];
  await page.route('**/api/v1/settings/on-call', async (route) => {
    posted.push(route.request().postDataJSON());
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', sections: {} }) });
  });
  await openOnCall(page);
  for (const group of [primary(page), backup(page)]) {
    await expect(telegram(group), 'Telegram stays checked').toBeChecked();
    await expect(telegram(group), 'and can be chosen').toBeEnabled();
    await expect(telegram(group), 'with no line describing it').toHaveAccessibleDescription('');
    await expect(mail(group), 'Email stays checked').toBeChecked();
  }
  await expect(page.getByText("hasn't paired Telegram"), 'no unpaired line shows for anyone').toHaveCount(0);
  const before = found as OnCallStored;
  const changed = before.escalationMinutes === 21 ? 22 : 21;
  await minutes(page).fill(String(changed));
  await saveButton(page).click();
  await expect(savedText(page), 'the routed save is shown as saved').toBeVisible();
  expect(posted.length, 'one save was posted').toBe(1);
  expect(posted[0], 'its body carries the stored person, address and channels of both roles, and the new minutes').toMatchObject({
    primaryPerson: 'user',
    primaryUser: README_ACCOUNT.user,
    primaryEmail: `zz-o12p-${tag}@example.com`,
    primaryChannels: 'telegram,email',
    backupPerson: 'user',
    backupUser: gone,
    backupEmail: `zz-o12b-${tag}@example.com`,
    backupChannels: 'telegram,email',
    escalationMinutes: changed,
  });
  expect(await readOnCall(page.request), 'nothing was written: the route answered it').toEqual(found);
});

test('O13: a stored user with no session row keeps their boxes, and saving shows the unknown-user text and changes nothing', async ({ page }) => {
  test.setTimeout(180_000);
  const tag = stamp();
  const user = `zzo13${tag}`;
  const ref = await seedOtherSession(user);
  try {
    const saved = await page.request.post(ON_CALL_API, {
      headers: envelope(),
      data: {
        primaryPerson: 'user',
        primaryUser: user,
        primaryEmail: `zz-o13-${tag}@example.com`,
        primaryChannels: 'email',
        backupPerson: 'nobody',
        backupUser: '',
        backupEmail: '',
        backupChannels: 'telegram,email',
        escalationMinutes: (found as OnCallStored).escalationMinutes,
      },
    });
    expect(saved.status(), `the user is saved as the on-call person: ${await saved.text()}`).toBe(200);
    await cleanFixtureRows([ref]);
    const stored = await readOnCall(page.request);
    expect(stored.primaryUser, 'the stored person is the user').not.toBe('');
    expect(
      stored.users.some((one) => one.user === stored.primaryUser),
      'who has no session row now, so the list does not hold them',
    ).toBe(false);
    const mark = await auditMark();
    await openOnCall(page);
    await expect(person(primary(page)), 'the Person select shows the gone user').toHaveValue(`user:${stored.primaryUser}`);
    await expect(telegram(primary(page)), 'Telegram can be chosen').toBeEnabled();
    await expect(telegram(primary(page)), 'and stays unchecked, as stored').not.toBeChecked();
    await expect(mail(primary(page)), 'Email stays checked').toBeChecked();
    await expect(page.getByText("hasn't paired Telegram"), 'no unpaired line shows').toHaveCount(0);
    await saveButton(page).click();
    await expect(page.locator('#oncall-primary-person-error'), 'the save is refused with the unknown-user text').toHaveText(UNKNOWN_USER(stored.primaryUser));
    await expect(savedText(page), 'with no saved text').toHaveCount(0);
    expect(await readOnCall(page.request), 'nothing was changed').toEqual(stored);
    expect(await auditSince(mark, 0), 'and nothing was audited').toEqual([]);
  } finally {
    await cleanFixtureRows([ref]);
  }
});

test('O14: a listed user who has not paired keeps the unpaired line while a stored backup the list lacks keeps a Telegram-only channel, and a save sends each', async ({ page }) => {
  test.setTimeout(180_000);
  const tag = stamp();
  const unpaired = `zz-o14-bob-${tag}`;
  const gone = `zz-o14-gone-${tag}`;
  await page.route('**/api/v1/settings', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    const response = await route.fetch();
    const body = (await response.json()) as { sections: { 'on-call': OnCallStored } };
    Object.assign(body.sections['on-call'], {
      users: [
        { user: `zz-o14-alice-${tag}`, paired: true },
        { user: unpaired, paired: false },
      ],
      primaryUser: unpaired,
      primaryEmail: `zz-o14p-${tag}@example.com`,
      primaryChannels: 'telegram,email',
      backupUser: gone,
      backupEmail: `zz-o14b-${tag}@example.com`,
      backupChannels: 'telegram',
    });
    await route.fulfill({ response, json: body });
  });
  const posted: unknown[] = [];
  await page.route('**/api/v1/settings/on-call', async (route) => {
    posted.push(route.request().postDataJSON());
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', sections: {} }) });
  });
  await openOnCall(page);
  await expect(telegram(primary(page)), 'a listed user who has not paired has Telegram disabled').toBeDisabled();
  await expect(telegram(primary(page)), 'and unchecked').not.toBeChecked();
  await expect(telegram(primary(page)), 'with the filled text').toHaveAccessibleDescription(
    `${unpaired} hasn't paired Telegram, so OcuTalon can't message them there yet. They can pair it on their own OcuTalon page.`,
  );
  await expect(mail(primary(page)), 'Email stays checked').toBeChecked();
  await expect(telegram(backup(page)), 'a stored backup the list lacks has Telegram enabled').toBeEnabled();
  await expect(telegram(backup(page)), 'and checked, as stored').toBeChecked();
  await expect(telegram(backup(page)), 'with no line describing it').toHaveAccessibleDescription('');
  await expect(mail(backup(page)), 'and Email unchecked, as stored').not.toBeChecked();
  await expect(page.getByText("hasn't paired Telegram"), 'the unpaired line shows once, for the listed user only').toHaveCount(1);
  const before = found as OnCallStored;
  const changed = before.escalationMinutes === 21 ? 22 : 21;
  await minutes(page).fill(String(changed));
  await saveButton(page).click();
  await expect(savedText(page), 'the routed save is shown as saved').toBeVisible();
  expect(posted.length, 'one save was posted').toBe(1);
  expect(posted[0], 'its body sends Email alone for the unpaired user and Telegram alone for the backup').toMatchObject({
    primaryUser: unpaired,
    primaryChannels: 'email',
    backupUser: gone,
    backupChannels: 'telegram',
    escalationMinutes: changed,
  });
});

test('O15: while the list is unavailable and nobody is on call, a stored backup keeps a Telegram-only channel, and a save sends it', async ({ page }) => {
  test.setTimeout(180_000);
  const tag = stamp();
  const gone = `zz-o15-gone-${tag}`;
  await page.route('**/api/v1/settings', async (route) => {
    if (route.request().method() !== 'GET') {
      await route.continue();
      return;
    }
    const response = await route.fetch();
    const body = (await response.json()) as { sections: { 'on-call': OnCallStored } };
    Object.assign(body.sections['on-call'], { users: [], backupUser: gone, backupEmail: `zz-o15-${tag}@example.com`, backupChannels: 'telegram' });
    await route.fulfill({ response, json: body });
  });
  const posted: unknown[] = [];
  await page.route('**/api/v1/settings/on-call', async (route) => {
    posted.push(route.request().postDataJSON());
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', sections: {} }) });
  });
  await openOnCall(page);
  await expect(person(primary(page)), 'the on-call person is Nobody').toHaveValue('nobody');
  await expect(person(backup(page)), 'the Person select shows the stored backup').toHaveValue(`user:${gone}`);
  await expect(telegram(backup(page)), 'Telegram stays checked').toBeChecked();
  await expect(telegram(backup(page)), 'and can be chosen').toBeEnabled();
  await expect(telegram(backup(page)), 'with no line describing it').toHaveAccessibleDescription('');
  await expect(mail(backup(page)), 'Email stays unchecked').not.toBeChecked();
  await expect(page.getByText("hasn't paired Telegram"), 'no unpaired line shows').toHaveCount(0);
  const before = found as OnCallStored;
  const changed = before.escalationMinutes === 21 ? 22 : 21;
  await minutes(page).fill(String(changed));
  await saveButton(page).click();
  await expect(savedText(page), 'the routed save is shown as saved').toBeVisible();
  expect(posted.length, 'one save was posted').toBe(1);
  expect(posted[0], 'its body keeps Nobody and sends the backup with Telegram alone').toMatchObject({
    primaryPerson: 'nobody',
    backupPerson: 'user',
    backupUser: gone,
    backupChannels: 'telegram',
    escalationMinutes: changed,
  });
});

test('O16: a stored backup with no session row keeps their boxes, and saving shows the unknown-user text under the backup and changes nothing', async ({ page }) => {
  test.setTimeout(180_000);
  const tag = stamp();
  const user = `zzo16${tag}`;
  const ref = await seedOtherSession(user);
  try {
    const saved = await page.request.post(ON_CALL_API, {
      headers: envelope(),
      data: {
        primaryPerson: 'nobody',
        primaryUser: '',
        primaryEmail: '',
        primaryChannels: 'telegram,email',
        backupPerson: 'user',
        backupUser: user,
        backupEmail: `zz-o16-${tag}@example.com`,
        backupChannels: 'email',
        escalationMinutes: (found as OnCallStored).escalationMinutes,
      },
    });
    expect(saved.status(), `the user is saved as the backup: ${await saved.text()}`).toBe(200);
    await cleanFixtureRows([ref]);
    const stored = await readOnCall(page.request);
    expect(stored.backupUser, 'the stored backup is the user').not.toBe('');
    expect(
      stored.users.some((one) => one.user === stored.backupUser),
      'who has no session row now, so the list does not hold them',
    ).toBe(false);
    const mark = await auditMark();
    await openOnCall(page);
    await expect(person(backup(page)), 'the Person select shows the gone backup').toHaveValue(`user:${stored.backupUser}`);
    await expect(telegram(backup(page)), 'Telegram can be chosen').toBeEnabled();
    await expect(telegram(backup(page)), 'and stays unchecked, as stored').not.toBeChecked();
    await expect(mail(backup(page)), 'Email stays checked').toBeChecked();
    await expect(page.getByText("hasn't paired Telegram"), 'no unpaired line shows').toHaveCount(0);
    await saveButton(page).click();
    await expect(page.locator('#oncall-backup-person-error'), 'the save is refused with the unknown-user text under the backup').toHaveText(UNKNOWN_USER(stored.backupUser));
    await expect(page.locator('#oncall-primary-person-error'), 'and none under the on-call person').toHaveCount(0);
    await expect(savedText(page), 'with no saved text').toHaveCount(0);
    expect(await readOnCall(page.request), 'nothing was changed').toEqual(stored);
    expect(await auditSince(mark, 0), 'and nothing was audited').toEqual([]);
  } finally {
    await cleanFixtureRows([ref]);
  }
});
