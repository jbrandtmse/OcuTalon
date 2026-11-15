import { expect, test, type Locator, type Page } from '../support/fixtures';

import { README_ACCOUNT, envelope } from '../sign-in/helpers';
import { readmeSession } from '../support/demo-path';
import { signInReadmeLoaded } from '../support/floor';
import { announcements, recordAnnouncements } from '../support/page';
import { PARTNER_API, aProduction, auditMark, auditSince, forProduction, partnerMember, removeZzContacts, type PartnerProduction } from '../support/partner-contacts';

/**
 * Story 24.2, the Partner contacts section of Settings in a real browser, signed in as the README admin (P1 to P9; the sign-in-2 unit). The section shows only while the
 * real GET /v1/settings carries the `partner-contacts` member, which it does only once OcuTalon.Fix.PartnerContacts has TABLE = 1 (Story 23.13). So these cases simulate
 * that one state and nothing else: a `page.route` on every settings answer fetches the real answer, then adds `sections['partner-contacts']` as the server's own
 * PartnerValues() builds it in a fresh IRIS process. The POSTs reach the real route, SecretHandoff, SettingsOps and the real rows and audit log. The cases run one
 * after the other and each is self-contained: the contacts that a case makes have names that begin zz-, and afterAll removes any that survive.
 *   P1  the nav link, the heading, the help line, a labelled control for every field, the Productions it concerns boxes and the keyboard order;
 *   P2  an add: the saved text, the new contact's group, the stored row, ForProduction in a fresh process and the one audit entry (the field names, the admin, the session);
 *   P3  a bad address and no production mark both fields, focus the address, and change nothing;
 *   P4  an edit of the address (one entry naming `email`), and a Remove that asks first: Cancel keeps the contact, the confirmation removes it and its audit entry;
 *   P5  a failed add (a routed 500) shows the failed text under the button, and changes and audits nothing;
 *   P6  a 409 shows the off-demo text in place of the forms;
 *   P7  a 403 shows the denied view in place of the section, and nothing is saved;
 *   P8  (QA) an empty name and a bad address, on the real server, mark both fields with their accepted texts and focus the name, the first of them in the form;
 *   P9  (QA) a 400 that names no field (a body of the wrong shape) shows the failed text under the button and marks no field.
 * The texts are written out here as the oracle.
 */
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const HELP = 'Partner warnings go only to the people listed here, and only after you approve each one.';
const BAD_EMAIL = 'Enter an email address such as name@example.com. Nothing was changed.';
const BAD_NAME = 'Enter a name of 1 to 128 characters. Nothing was changed.';
const NO_PRODUCTION = 'Choose at least one production. Nothing was changed.';
const FAILED = "Couldn't save. Nothing was changed.";
const OFF_ON_DEMO = 'Partner contacts are off on the online demo, where partner warnings go to simulated contacts. They work on your own install.';
const DENIED = 'Only OcuTalon admins can open settings.';

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });
const addGroup = (page: Page): Locator => page.getByRole('group', { name: 'Add contact', exact: true });
const nameOf = (group: Locator): Locator => group.getByLabel('Name', { exact: true });
const addressOf = (group: Locator): Locator => group.getByLabel('Email address', { exact: true });
const productionsOf = (group: Locator): Locator => group.getByRole('group', { name: 'Productions it concerns', exact: true });
const boxOf = (group: Locator, production: PartnerProduction): Locator => productionsOf(group).getByRole('checkbox', { name: production.displayName, exact: true });
const contactGroup = (page: Page, name: string): Locator => page.getByRole('group', { name, exact: true });
const savedIn = (group: Locator): Locator => group.locator('p.saved').filter({ hasText: SAVED });

test.describe.configure({ mode: 'serial' });

/** A tag for the names of the run. */
const stamp = `${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

test.beforeAll(async () => {
  await removeZzContacts();
});

test.afterAll(async () => {
  await removeZzContacts();
});

test.beforeEach(async ({ page }) => {
  await recordAnnouncements(page);
  await page.route('**/api/v1/settings**', async (route) => {
    const response = await route.fetch();
    const type = response.headers()['content-type'] ?? '';
    if (response.status() !== 200 || !type.includes('application/json')) {
      await route.fulfill({ response });
      return;
    }
    const body = (await response.json()) as { sections?: Record<string, unknown> };
    if (body.sections === undefined || typeof body.sections !== 'object') {
      await route.fulfill({ response });
      return;
    }
    body.sections['partner-contacts'] = await partnerMember();
    await route.fulfill({ response, json: body });
  });
  await signInReadmeLoaded(page);
});

/** Opens Settings > Partner contacts from the header and the sections navigation. */
async function openPartners(page: Page): Promise<void> {
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Partner contacts', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Partner contacts' })).toBeVisible();
  await expect(addGroup(page)).toBeVisible();
}

test('P1: the section has its nav link, heading, help and a labelled control for every field, and a keyboard order', async ({ page }) => {
  test.setTimeout(180_000);
  const production = await aProduction();
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await expect(sectionsNav(page).getByRole('link', { name: 'Partner contacts', exact: true }), 'Partner contacts is listed, after On call').toBeVisible();
  const links = await sectionsNav(page).getByRole('link').allTextContents();
  expect(links.indexOf('Partner contacts'), 'after On call').toBe(links.indexOf('On call') + 1);
  await sectionsNav(page).getByRole('link', { name: 'Partner contacts', exact: true }).click();
  expect(new URL(page.url()).hash, 'Partner contacts has its own address').toBe('#/settings/partner-contacts');
  await expect(page.getByRole('heading', { level: 2, name: 'Partner contacts' })).toBeVisible();
  await expect(sectionsNav(page).getByRole('link', { name: 'Partner contacts', exact: true }), 'its link is the current one').toHaveAttribute('aria-current', 'true');
  await expect(page, 'the page keeps its title').toHaveTitle('Settings \u00B7 OcuTalon');
  await expect(page.getByText(HELP, { exact: true }), 'the help line, word for word').toBeVisible();
  await expect(page.getByText("isn't built yet"), 'no "not yet" text').toHaveCount(0);

  const group = addGroup(page);
  await expect(nameOf(group), 'a labelled Name field').toBeVisible();
  await expect(addressOf(group), 'a labelled Email address field').toBeVisible();
  await expect(productionsOf(group), 'a Productions it concerns group').toBeVisible();
  await expect(boxOf(group, production), 'with a box labelled by the production').toBeVisible();
  await expect(group.getByRole('button', { name: 'Add contact', exact: true }), 'and the Add contact button').toBeVisible();

  // The keyboard order: Name, Email address, each production's box, Add contact.
  await nameOf(group).focus();
  await page.keyboard.press('Tab');
  await expect(addressOf(group), 'Tab goes to the address').toBeFocused();
  const member = await partnerMember();
  for (const one of member.productions) {
    await page.keyboard.press('Tab');
    await expect(boxOf(group, one), `then the box of ${one.displayName}`).toBeFocused();
  }
  await page.keyboard.press('Space');
  await expect(boxOf(group, member.productions[member.productions.length - 1]), 'Space ticks it').toBeChecked();
  await page.keyboard.press('Space');
  await expect(boxOf(group, member.productions[member.productions.length - 1]), 'and clears it').not.toBeChecked();
  await page.keyboard.press('Tab');
  await expect(group.getByRole('button', { name: 'Add contact', exact: true }), 'then Add contact').toBeFocused();
});

test('P2: an add shows the saved text and the new contact, and the stored row, ForProduction and the audit entry match', async ({ page }) => {
  test.setTimeout(240_000);
  const production = await aProduction();
  const made = `zz-p2-${stamp} Partner`;
  const madeAddress = `zz-p2-${stamp}@example.com`;
  const before = await partnerMember();
  const mark = await auditMark();
  await openPartners(page);
  const group = addGroup(page);
  await nameOf(group).fill(made);
  await addressOf(group).fill(madeAddress);
  await boxOf(group, production).check();
  await group.getByRole('button', { name: 'Add contact', exact: true }).click();
  await expect(savedIn(group), 'the saved text shows').toBeVisible();
  await expect.poll(() => announcements(page, SAVED), 'and is announced once').toBe(1);
  await expect(contactGroup(page, made), 'the new contact has its own group').toBeVisible();
  await expect(nameOf(group), 'the Add contact form is empty again').toHaveValue('');

  const after = await partnerMember();
  const stored = after.contacts.find((one) => one.name === made);
  expect(after.contacts.length, 'one contact more').toBe(before.contacts.length + 1);
  expect(stored?.email, 'the row holds the address').toBe(madeAddress);
  expect(stored?.productions, 'and the production').toEqual([{ namespace: production.namespace, production: production.production }]);
  const given = await forProduction(production.namespace, production.production);
  expect(given.map((one) => [one.name, one.address]), 'ForProduction in a fresh process gives it').toContainEqual([made, madeAddress]);

  const entries = await auditSince(mark, 1);
  expect(entries.length, 'one audit entry').toBe(1);
  const session = await readmeSession();
  expect(
    [entries[0].setting, entries[0].from, entries[0].to, entries[0].irisUser, entries[0].sessionRef, entries[0].channel],
    'it names the fields and no value, the admin, the session and the web channel',
  ).toEqual([`partnerContact.${stored?.ref ?? ''}`, '', 'name,email,productions', README_ACCOUNT.user, session.ref, 'web']);
  expect(JSON.stringify(entries), 'neither the name nor the address is in the entry').not.toContain(made);
  expect(JSON.stringify(entries), 'neither the address').not.toContain(madeAddress);
});

test('P3: a bad address and no production mark both fields, focus the address, and change nothing', async ({ page }) => {
  test.setTimeout(240_000);
  const before = await partnerMember();
  const mark = await auditMark();
  await openPartners(page);
  const group = addGroup(page);
  await nameOf(group).fill(`zz-p3-${stamp} Partner`);
  await addressOf(group).fill('nope');
  await group.getByRole('button', { name: 'Add contact', exact: true }).click();
  await expect(page.locator('#partner-new-email-error'), 'the bad address shows its text').toHaveText(BAD_EMAIL);
  await expect(page.locator('#partner-new-productions-error'), 'no production shows its text').toHaveText(NO_PRODUCTION);
  await expect(addressOf(group), 'the address is marked invalid').toHaveAttribute('aria-invalid', 'true');
  await expect(addressOf(group), 'and linked to its error').toHaveAttribute('aria-describedby', 'partner-new-email-error');
  await expect(productionsOf(group), 'the productions group is linked to its error').toHaveAttribute('aria-describedby', 'partner-new-productions-error');
  await expect(addressOf(group), 'the first field in error takes focus').toBeFocused();
  await expect(page.locator('#partner-new-name-error'), 'the name has no error').toHaveCount(0);
  await expect(savedIn(group), 'no saved text').toHaveCount(0);
  expect((await partnerMember()).contacts, 'nothing was changed').toEqual(before.contacts);
  expect(await auditSince(mark, 0, 2), 'and nothing was audited').toEqual([]);
});

test('P4: an edit is audited with the changed field, and a Remove asks first, then removes the contact and audits it', async ({ page }) => {
  test.setTimeout(300_000);
  const production = await aProduction();
  const made = `zz-p4-${stamp} Partner`;
  const madeAddress = `zz-p4-${stamp}-before@example.com`;
  const added = await page.request.post(PARTNER_API, {
    headers: envelope(),
    data: { action: 'save', ref: '', name: made, email: madeAddress, productions: [{ namespace: production.namespace, production: production.production }] },
  });
  expect(added.status(), await added.text()).toBe(200);
  const stored = (await partnerMember()).contacts.find((one) => one.name === made);
  expect(stored, 'the contact of this case is stored').toBeTruthy();
  const newAddress = `zz-p4-${stamp}-after@example.com`;
  const mark = await auditMark();
  await openPartners(page);
  const group = contactGroup(page, made);
  await expect(addressOf(group), 'the contact shows its stored address').toHaveValue(madeAddress);
  await expect(boxOf(group, production), 'and its production ticked').toBeChecked();
  await addressOf(group).fill(newAddress);
  await page.getByRole('button', { name: `Save changes ${made}`, exact: true }).click();
  await expect(savedIn(group), 'the edit shows the saved text').toBeVisible();
  const given = await forProduction(production.namespace, production.production);
  expect(given.map((one) => [one.name, one.address]), 'ForProduction gives the new address at once').toContainEqual([made, newAddress]);
  expect(given.map((one) => one.address), 'and not the old one').not.toContain(madeAddress);
  let entries = await auditSince(mark, 1);
  expect(entries.map((one) => [one.setting, one.from, one.to]), 'one audit entry naming only the changed field').toEqual([[`partnerContact.${stored?.ref ?? ''}`, 'email', 'email']]);

  // Remove asks first: Cancel keeps the contact and gives focus back to the button.
  const remove = page.getByRole('button', { name: `Remove ${made}`, exact: true });
  await remove.click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByRole('heading', { level: 2 }), 'the question names the contact and the address').toHaveText(`Remove ${made}? Partner warnings will stop going to ${newAddress}.`);
  await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(remove, 'focus returns to the Remove button').toBeFocused();
  expect((await partnerMember()).contacts.map((one) => one.name), 'Cancel keeps the contact').toContain(made);

  await remove.click();
  await dialog.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(contactGroup(page, made), 'the contact is gone from the page').toHaveCount(0);
  expect((await partnerMember()).contacts.map((one) => one.name), 'and from the rows').not.toContain(made);
  expect((await forProduction(production.namespace, production.production)).map((one) => one.name), 'ForProduction no longer gives it').not.toContain(made);
  entries = await auditSince(mark, 2);
  expect(entries.map((one) => [one.setting, one.from, one.to]), 'the removal has its own entry, from the field names to nothing').toEqual([
    [`partnerContact.${stored?.ref ?? ''}`, 'email', 'email'],
    [`partnerContact.${stored?.ref ?? ''}`, 'name,email,productions', ''],
  ]);
  await expect.poll(() => announcements(page, SAVED), 'the edit and the removal were each announced once').toBe(2);
});

/** Fills the Add contact form with a valid contact of this case and presses Add contact; nothing reaches the server when the route is faked. */
async function addValid(page: Page, tag: string): Promise<Locator> {
  const production = await aProduction();
  const group = addGroup(page);
  await nameOf(group).fill(`zz-${tag}-${stamp} Partner`);
  await addressOf(group).fill(`zz-${tag}-${stamp}@example.com`);
  await boxOf(group, production).check();
  await group.getByRole('button', { name: 'Add contact', exact: true }).click();
  return group;
}

/** Answers every POST to the partner route with the given status and body; other methods go on to the settings route of beforeEach. */
async function answerPost(page: Page, status: number, body: unknown): Promise<void> {
  await page.route('**/api/v1/settings/partner-contacts', async (route) => {
    if (route.request().method() !== 'POST') {
      await route.fallback();
      return;
    }
    await route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
  });
}

test('P5: a failed add shows the failed text under the button, and changes and audits nothing', async ({ page }) => {
  test.setTimeout(240_000);
  const before = await partnerMember();
  const mark = await auditMark();
  await answerPost(page, 500, { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } });
  await openPartners(page);
  const group = await addValid(page, 'p5');
  await expect(page.locator('#partner-new-error'), 'the error is under the button').toHaveText(FAILED);
  await expect(group.getByRole('button', { name: 'Add contact', exact: true }), 'the button is described by it').toHaveAttribute('aria-describedby', 'partner-new-error');
  await expect(group.getByRole('button', { name: 'Add contact', exact: true }), 'and is restored').not.toHaveAttribute('aria-busy', 'true');
  await expect(savedIn(group), 'no saved text').toHaveCount(0);
  expect((await partnerMember()).contacts, 'nothing was changed').toEqual(before.contacts);
  expect(await auditSince(mark, 0, 2), 'and nothing was audited').toEqual([]);
});

test('P6: a 409 shows the off-demo text in place of the forms', async ({ page }) => {
  test.setTimeout(240_000);
  await answerPost(page, 409, { error: { code: 'not_available', message: OFF_ON_DEMO } });
  await openPartners(page);
  await addValid(page, 'p6');
  await expect(page.getByText(OFF_ON_DEMO, { exact: true }), 'a 409 shows the off-demo text').toBeVisible();
  await expect(addGroup(page), 'in place of the form').toHaveCount(0);
  await expect(page.getByText(HELP, { exact: true }), 'with no help for the form').toHaveCount(0);
});

test('P7: a 403 shows the denied view in place of the section, and nothing is saved', async ({ page }) => {
  test.setTimeout(240_000);
  const before = await partnerMember();
  await answerPost(page, 403, { error: { code: 'not_admin', message: DENIED } });
  await openPartners(page);
  const group = await addValid(page, 'p7');
  await expect(page.locator('p.denied'), 'the page shows its denied text').toHaveText(DENIED);
  await expect(group, 'in place of the form').toHaveCount(0);
  await expect(page.locator('p.saved'), 'with no saved text').toHaveCount(0);
  expect((await partnerMember()).contacts, 'nothing was changed').toEqual(before.contacts);
});

test('P8: an empty name and a bad address mark both fields with their texts, focus the name, and change nothing', async ({ page }) => {
  test.setTimeout(240_000);
  const production = await aProduction();
  const before = await partnerMember();
  const mark = await auditMark();
  await openPartners(page);
  const group = addGroup(page);
  await addressOf(group).fill('nope');
  await boxOf(group, production).check();
  await group.getByRole('button', { name: 'Add contact', exact: true }).click();
  await expect(page.locator('#partner-new-name-error'), 'the empty name shows its text').toHaveText(BAD_NAME);
  await expect(page.locator('#partner-new-email-error'), 'the bad address shows its text').toHaveText(BAD_EMAIL);
  await expect(nameOf(group), 'the name is marked invalid').toHaveAttribute('aria-invalid', 'true');
  await expect(nameOf(group), 'and linked to its error').toHaveAttribute('aria-describedby', 'partner-new-name-error');
  await expect(nameOf(group), 'the first field in the form takes focus, not the address').toBeFocused();
  await expect(page.locator('#partner-new-productions-error'), 'the ticked production has no error').toHaveCount(0);
  await expect(savedIn(group), 'no saved text').toHaveCount(0);
  expect((await partnerMember()).contacts, 'nothing was changed').toEqual(before.contacts);
  expect(await auditSince(mark, 0, 2), 'and nothing was audited').toEqual([]);
});

test('P9: a 400 that names no field shows the failed text under the button and marks no field', async ({ page }) => {
  test.setTimeout(240_000);
  const before = await partnerMember();
  await answerPost(page, 400, { error: { code: 'bad_settings', message: FAILED }, fields: [] });
  await openPartners(page);
  const group = await addValid(page, 'p9');
  await expect(page.locator('#partner-new-error'), 'the failed text is under the button').toHaveText(FAILED);
  await expect(group.getByRole('button', { name: 'Add contact', exact: true }), 'the button is described by it').toHaveAttribute('aria-describedby', 'partner-new-error');
  await expect(page.locator('#partner-new-name-error, #partner-new-email-error, #partner-new-productions-error'), 'no field is marked').toHaveCount(0);
  await expect(savedIn(group), 'no saved text').toHaveCount(0);
  expect((await partnerMember()).contacts, 'nothing was changed').toEqual(before.contacts);
});
