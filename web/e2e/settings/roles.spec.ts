import { expect, test, type APIResponse, type Locator, type Page } from '../support/fixtures';

import { STATE, changeSnapshot } from '../support/api';
import { signInReadmeLoaded } from '../support/floor';
import { fixtureUser } from '../support/iris';

/**
 * Story 25.4, the Roles section of Settings in a real browser, signed in as the README admin (RS1 and RS2; the sign-in-2 unit). The roles' existence is the one thing the
 * server cannot show on this branch (Story 26.4 creates them), so RS2 answers /state with `rolesAssignable: true`; the list, the grant and the removal go to the real
 * routes and the real production, and the ZzRoleTarget fixture user (role OcuTalonUser) is the account whose roles change. Every case puts the target's roles back.
 *   RS1  on the real state the Settings navigation has no Roles entry, and #/settings/roles opens Models;
 *   RS2  with rolesAssignable true the nav lists Roles last; the section lists from the real route; by keyboard alone the admin grants OcuTalonViewer to the target and
 *        sees the saved text, then removes it with the target's Remove viewer button, sees the text again and finds focus on the list heading; an unknown user shows
 *        the refusal text; every control is reached by its label;
 *   RS3  a save that changes nothing shows "No change: {user}'s roles are already as you set them." and not the saved text: the same grant again, and a Remove of a role that
 *        was taken away behind the page's back (the list is stale).
 */
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const UNKNOWN = 'There is no IRIS user with that name.';
const SYSTEM = "This is an IRIS system account, so its roles can't be changed here.";
const NO_CHANGE = (user: string): string => `No change: ${user}'s roles are already as you set them.`;
const ROLES = '/ocutalon/api/v1/settings/roles';
/** The name of the fixture account whose roles change: read when a case runs, because the listing of the specs has no fixture users. */
const target = (): string => fixtureUser('ROLETARGET').user;

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });

/** Grants or removes one role of the target through the real route, without the page; the server's answer. */
async function change(page: Page, role: string, grant: boolean): Promise<APIResponse> {
  return page.request.post(ROLES, { headers: { 'content-type': 'application/json', 'x-ocutalon-request': '1', origin: new URL(page.url()).origin }, data: { user: target(), role, grant } });
}

/** Puts the target's roles back: removes the two assignable roles through the real route. */
async function restore(page: Page): Promise<void> {
  for (const role of ['OcuTalonViewer', 'OcuTalonApprover']) {
    await change(page, role, false);
  }
}

test('RS1: on the real state there is no Roles entry in the Settings navigation', async ({ page }) => {
  await signInReadmeLoaded(page);
  const state = (await (await page.request.get(STATE)).json()) as Record<string, unknown>;
  expect(state['rolesAssignable'], 'the real state: no STEP6ROLES on this branch').toBe(false);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await expect(sectionsNav(page).getByRole('link'), 'seven sections, no Roles').toHaveText(['Models', 'Budgets', 'Channels', 'Daily digest', 'Time zone', 'Check thresholds', 'Demo mode']);
  await page.evaluate(() => {
    location.hash = '#/settings/roles';
  });
  await expect(page.getByRole('heading', { level: 2 }), 'the address of a hidden Roles opens Models').toHaveText('Models');
});

test('RS2: with roles assignable, the admin lists, grants and removes by keyboard, and an unknown user is refused', async ({ page }) => {
  test.setTimeout(180_000);
  await changeSnapshot(page, (snapshot) => {
    snapshot['rolesAssignable'] = true;
  });
  await signInReadmeLoaded(page);
  try {
    await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
    await expect(sectionsNav(page).getByRole('link'), 'Roles is the last entry').toHaveText(['Models', 'Budgets', 'Channels', 'Daily digest', 'Time zone', 'Check thresholds', 'Demo mode', 'Tools and MCP servers', 'Roles']);
    const link = sectionsNav(page).getByRole('link', { name: 'Roles', exact: true });
    await link.focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('heading', { level: 2, name: 'Roles' })).toBeVisible();
    const section = page.getByRole('region', { name: 'Roles', exact: true });
    await expect(section.getByText("Approvers can answer the approval requests that reach them, for every kind of risky action. Viewers can open OcuTalon but can't chat, answer or change anything.", { exact: true })).toBeVisible();
    await expect(section.getByText('An approver role for one kind, such as OcuTalonApprover_resend, is granted in IRIS.', { exact: true })).toBeVisible();
    await expect(section.getByRole('heading', { level: 4, name: 'People with an OcuTalon role' })).toBeVisible();
    const row = section.getByRole('group', { name: target(), exact: true });
    await expect(row, 'the target is listed, from the real route').toBeVisible();
    await expect(row.getByText('OcuTalonUser', { exact: true })).toBeVisible();
    await expect(row.getByRole('button'), 'it holds no assignable role yet, so no Remove button').toHaveCount(0);
    await expect(section.getByRole('group', { name: 'ocutalon', exact: true }), 'the README account is listed too').toBeVisible();

    // Grant by keyboard only: the user field, the role select, the Grant button.
    await section.getByLabel('IRIS user name', { exact: true }).focus();
    await page.keyboard.type(target());
    await page.keyboard.press('Tab');
    await expect(section.getByLabel('Role', { exact: true })).toBeFocused();
    await page.keyboard.press('V');
    await expect(section.getByLabel('Role', { exact: true }), 'typing V chooses the viewer option').toHaveValue('OcuTalonViewer');
    await page.keyboard.press('Tab');
    await expect(section.getByRole('button', { name: 'Grant', exact: true })).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(section.getByText(SAVED, { exact: true }), 'the step 2 text shows').toBeVisible();
    await expect(row.getByText('OcuTalonUser, OcuTalonViewer', { exact: true }), 'the list is loaded again with the grant').toBeVisible();
    const remove = row.getByRole('button', { name: `Remove viewer from ${target()}`, exact: true });
    await expect(remove, 'and the row has its Remove viewer button, named by the user').toBeVisible();
    await expect(remove).toHaveText('Remove viewer');

    // Remove by keyboard.
    await remove.focus();
    await page.keyboard.press('Enter');
    await expect(section.getByText(SAVED, { exact: true }), 'the text again').toBeVisible();
    await expect(row.getByText('OcuTalonUser', { exact: true })).toBeVisible();
    await expect(row.getByRole('button'), 'the role is gone').toHaveCount(0);
    await expect(section.getByRole('heading', { level: 4, name: 'People with an OcuTalon role' }), 'focus goes to the list heading, as the pressed button is gone').toBeFocused();

    // Refusals show in the section.
    await section.getByLabel('IRIS user name', { exact: true }).fill('ZzNoSuchUser');
    await section.getByRole('button', { name: 'Grant', exact: true }).click();
    await expect(section.getByText(UNKNOWN, { exact: true })).toBeVisible();
    await section.getByLabel('IRIS user name', { exact: true }).fill('UnknownUser');
    await section.getByRole('button', { name: 'Grant', exact: true }).click();
    await expect(section.getByText(SYSTEM, { exact: true })).toBeVisible();
  } finally {
    await restore(page);
  }
});

test('RS3: a save that changes nothing says so, for a grant already held and for a removal of a role not held', async ({ page }) => {
  test.setTimeout(180_000);
  await changeSnapshot(page, (snapshot) => {
    snapshot['rolesAssignable'] = true;
  });
  await signInReadmeLoaded(page);
  try {
    await restore(page);
    await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
    await sectionsNav(page).getByRole('link', { name: 'Roles', exact: true }).click();
    const section = page.getByRole('region', { name: 'Roles', exact: true });
    const row = section.getByRole('group', { name: target(), exact: true });
    await expect(row, 'the target is listed').toBeVisible();
    await expect(row.getByText('OcuTalonUser', { exact: true }), 'the target starts with the user role only').toBeVisible();
    const status = section.locator('p.saved[data-roles="status"]');

    // The first grant changes the roles: the saved text.
    await section.getByLabel('IRIS user name', { exact: true }).fill(target());
    await section.getByLabel('Role', { exact: true }).selectOption('OcuTalonViewer');
    await section.getByRole('button', { name: 'Grant', exact: true }).click();
    await expect(status.locator('[data-saved="roles"]'), 'the grant that changes the roles shows the saved text').toHaveText(SAVED);
    await expect(row.getByText('OcuTalonUser, OcuTalonViewer', { exact: true })).toBeVisible();

    // The same grant again changes nothing: the no-change text with the user's name, and not the saved text.
    const reloaded = page.waitForResponse((response) => new URL(response.url()).pathname === ROLES && response.request().method() === 'GET');
    await section.getByLabel('IRIS user name', { exact: true }).fill(target());
    await section.getByRole('button', { name: 'Grant', exact: true }).click();
    await expect(status.locator('[data-saved="roles-no-change"]'), 'a grant of a role the user already holds shows the no-change text').toHaveText(NO_CHANGE(target()));
    await expect(section.getByText(SAVED, { exact: true }), 'and not the saved text').toHaveCount(0);
    await reloaded;

    // Once the list has been read again, the role is taken away behind the page's back, so the list is stale: its Remove button now removes a role the user does not hold.
    const remove = row.getByRole('button', { name: `Remove viewer from ${target()}`, exact: true });
    await expect(remove, 'the stale list still offers Remove viewer').toBeVisible();
    const removed = await change(page, 'OcuTalonViewer', false);
    expect(removed.status(), 'the removal behind the page\'s back is accepted').toBe(200);
    expect(await removed.json(), 'and changes the roles').toMatchObject({ result: 'done', changed: true });
    await remove.click();
    await expect(status.locator('[data-saved="roles-no-change"]'), 'a removal of a role the user does not hold shows the no-change text').toHaveText(NO_CHANGE(target()));
    await expect(section.getByText(SAVED, { exact: true }), 'and not the saved text').toHaveCount(0);
    await expect(row.getByRole('button'), 'the list is loaded again without the role').toHaveCount(0);
    await expect(section.getByRole('heading', { level: 4, name: 'People with an OcuTalon role' }), 'focus goes to the list heading, as the pressed button is gone').toBeFocused();
  } finally {
    await restore(page);
  }
});
