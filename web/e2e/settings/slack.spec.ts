import { expect, test, type Locator, type Page } from '../support/fixtures';

import { README_ACCOUNT } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';
import { chk, irisScript, quoted } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 27.3, the Slack group of Settings > Channels in a real browser, signed in as the README admin (the sign-in-2 unit; the stack has no SLACK_* variable, so Slack is off):
 *   SS1  the group is a region named Slack, made from its lazy chunk: the not-set-up line and the How to set it up link (to GUIDE.md#slack, in a new tab), the members help,
 *        the empty list text and the form (the member ID field, the user picker with the README user, Link member);
 *   SS2  a link with no noted workspace shows its refusal under the button; with the workspace noted (seeded, and removed after), the README user is linked: the saved line shows, the row
 *        appears with the user and the member ID and an Unlink button described by its row, the form empties; Unlink removes the row and shows the unlinked line and the empty text;
 *   SS3  a member ID of the wrong shape shows its text under the field, takes focus and sends no request; typing clears it;
 *   SS4  an online-demo answer (409 not_available, fulfilled by the test) shows only the off-on-demo line;
 *   SS5  a list that says Slack is on shows "Slack on" and the address to subscribe to, on this page's origin;
 *   SS6  a list that fails to load shows the load error with Retry in place of the group's body, announced once, and Retry loads it.
 * The texts are written out here as the oracle. Every case removes the links it made.
 */
const SLACK = '/ocutalon/api/v1/settings/channels/slack';
const TEAM = 'T0E2E0002';
const NOT_SET_UP = 'Slack not set up. Add SLACK_BOT_TOKEN and SLACK_SIGNING_SECRET to .env and restart OcuTalon.';
const HELP = 'Only direct messages to the bot from a linked member become chat turns. Everything else from Slack is recorded in Visual Trace and goes no further.';
const NO_MEMBERS = 'No Slack members are linked yet.';
const OFF = 'Slack is off on the online demo, so it has no public Slack address. It works on your own install.';
const BAD_MEMBER = 'Enter a Slack member ID such as U012AB3CDE: a U or W followed by letters and digits. Nothing was changed.';
const LINKED = 'Linked. Their direct messages to the bot now reach OcuTalon. Recorded in the audit log.';
const UNLINKED = 'Unlinked. Their messages no longer reach OcuTalon. Recorded in the audit log.';
const NO_WORKSPACE = "OcuTalon hasn't had an event from your Slack workspace yet. Ask the person to send the bot a direct message, then link them. Nothing was changed.";
const LOAD_FAILED = "Couldn't load your session.";

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });

/** Signs the README admin in and opens Settings > Channels; returns the Slack group. */
async function openSlack(page: Page): Promise<Locator> {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Channels', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Channels' })).toBeVisible();
  return page.getByRole('region', { name: 'Slack', exact: true });
}

/** A member ID of the case: U, then upper-case letters and digits. */
const memberOf = (): string => `U0E2E${Date.now().toString(36).toUpperCase()}${Math.floor(Math.random() * 1296).toString(36).toUpperCase()}`;

/** Notes the e2e workspace, or removes the noted one. */
async function workspace(on: boolean): Promise<void> {
  const lines = await irisScript(on ? `Do ##class(OcuTalon.Data.SlackLink).NoteWorkspace(${quoted(TEAM)}) Write !,"CHK|w|",##class(OcuTalon.Data.SlackLink).Workspace()` : 'Kill ^OcuTalonP.SlackW Write !,"CHK|w|"');
  expect(chk(lines, 'w'), 'the workspace is as set').toBe(on ? TEAM : '');
}

/** Removes every link row of the e2e workspace. */
async function dropLinks(): Promise<void> {
  const lines = await irisScript(`Do ##class(%SQL.Statement).%ExecDirect(,"DELETE FROM OcuTalon_Data.SlackLink WHERE TeamId = ?",${quoted(TEAM)}) Write !,"CHK|dropped|1"`);
  expect(chk(lines, 'dropped')).toBe('1');
}

/** The number of link rows of the e2e workspace. */
async function rowCount(): Promise<number> {
  const lines = await irisScript(`Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) c FROM OcuTalon_Data.SlackLink WHERE TeamId = ?",${quoted(TEAM)}) Do rs.%Next() Write !,"CHK|c|",rs.%Get("c")`);
  return Number(chk(lines, 'c') ?? '-1');
}

test('SS1: the group is made from its lazy chunk, with the not-set-up line, the how-to link and the members form', async ({ page }) => {
  test.setTimeout(120_000);
  const group = await openSlack(page);
  await expect(group.getByRole('heading', { level: 3, name: 'Slack', exact: true }), 'the group heading').toBeVisible();
  await expect(group.getByText(NOT_SET_UP, { exact: true }), 'Slack is not set up on this stack').toBeVisible();
  const howTo = group.getByRole('link', { name: 'How to set it up (opens in a new tab)', exact: true });
  await expect(howTo, 'with the link to the guide').toBeVisible();
  expect(await howTo.getAttribute('href'), 'which names the Slack section of GUIDE.md').toMatch(/GUIDE\.md#slack$/);
  await expect(howTo).toHaveAttribute('target', '_blank');
  await expect(howTo).toHaveAttribute('rel', 'noopener noreferrer');
  await expect(group.getByRole('heading', { level: 4, name: 'Linked Slack members', exact: true }), 'the members heading').toBeVisible();
  await expect(group.getByText(HELP, { exact: true }), 'the members help').toBeVisible();
  await expect(group.getByText(NO_MEMBERS, { exact: true }), 'no member is linked').toBeVisible();
  await expect(group.getByLabel('Slack member ID', { exact: true }), 'the member ID field').toBeVisible();
  const picker = group.getByLabel('OcuTalon user', { exact: true });
  await expect(picker, 'the user picker').toBeVisible();
  await expect(picker.locator('option', { hasText: README_ACCOUNT.user }), 'offers the README user').toHaveCount(1);
  await expect(group.getByRole('button', { name: 'Link member', exact: true }), 'and the Link member button').toBeVisible();
  await expect(group.getByText('Slack on', { exact: true }), 'there is no on line').toHaveCount(0);
});

test('SS2: a link shows its refusal when no workspace is noted, then makes a row with an Unlink button described by it, and Unlink removes it', async ({ page }) => {
  test.setTimeout(180_000);
  const member = memberOf();
  try {
    await dropLinks();
    await workspace(false);
    const group = await openSlack(page);
    const field = group.getByLabel('Slack member ID', { exact: true });
    await field.fill(member);
    await group.getByLabel('OcuTalon user', { exact: true }).selectOption(README_ACCOUNT.user);
    await group.getByRole('button', { name: 'Link member', exact: true }).click();
    await expect(group.locator('#slack-form-error'), 'no workspace: the refusal under the button').toHaveText(NO_WORKSPACE);
    expect(await rowCount(), 'no row was made').toBe(0);

    await workspace(true);
    await group.getByRole('button', { name: 'Link member', exact: true }).click();
    await expect(group.locator('[data-slack="saved"]'), 'the linked line shows').toHaveText(LINKED);
    await expect(field, 'the member ID field is emptied').toHaveValue('');
    const row = group.getByRole('group', { name: README_ACCOUNT.user, exact: true });
    await expect(row, 'the row appears').toHaveCount(1);
    await expect(row, 'with the user and the member ID').toContainText(member);
    await expect(group.getByText(NO_MEMBERS, { exact: true }), 'and the empty text goes').toHaveCount(0);
    expect(await rowCount(), 'one row is stored').toBe(1);
    const unlink = row.getByRole('button', { name: 'Unlink', exact: true });
    await expect(unlink, 'the Unlink button is described by its row').toHaveAccessibleDescription(new RegExp(`${README_ACCOUNT.user}\\s+${member}`));

    await unlink.click();
    await expect(group.locator('[data-slack="saved"]'), 'the unlinked line shows').toHaveText(UNLINKED);
    await expect(group.getByRole('group', { name: README_ACCOUNT.user, exact: true }), 'the row is gone').toHaveCount(0);
    await expect(group.getByText(NO_MEMBERS, { exact: true }), 'and the empty text is back').toBeVisible();
    expect(await rowCount(), 'no row is stored').toBe(0);
  } finally {
    await dropLinks();
    await workspace(false);
  }
});

test('SS3: a member ID of the wrong shape shows its text under the field and sends no request', async ({ page }) => {
  test.setTimeout(120_000);
  const group = await openSlack(page);
  let posts = 0;
  page.on('request', (request) => {
    if (request.method() === 'POST' && request.url().includes(SLACK)) posts += 1;
  });
  const field = group.getByLabel('Slack member ID', { exact: true });
  await field.fill('X1');
  await group.getByRole('button', { name: 'Link member', exact: true }).click();
  await expect(group.locator('#slack-member-error'), 'the text of the bad member ID').toHaveText(BAD_MEMBER);
  await expect(field, 'takes focus').toBeFocused();
  await expect(field).toHaveAttribute('aria-invalid', 'true');
  expect(posts, 'and no request was sent').toBe(0);
  await field.fill('U012AB3CDE');
  await expect(group.locator('#slack-member-error'), 'typing clears the error').toHaveCount(0);
});

test('SS4: an online-demo answer shows only the off-on-demo line', async ({ page }) => {
  test.setTimeout(120_000);
  await page.route(`**${SLACK}`, async (route) => {
    await route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_available', message: OFF } }) });
  });
  const group = await openSlack(page);
  await expect(group.getByText(OFF, { exact: true }), 'the group says that Slack is off on the demo').toBeVisible();
  await expect(group.getByText(NOT_SET_UP, { exact: true }), 'and nothing else of the state').toHaveCount(0);
  await expect(group.getByText(HELP, { exact: true }), 'no members help').toHaveCount(0);
  await expect(group.getByRole('button'), 'no button').toHaveCount(0);
  await expect(group.getByRole('textbox'), 'no field').toHaveCount(0);
  await expect(group.getByRole('link'), 'and no link').toHaveCount(0);
});

test('SS5: a list that says Slack is on shows the state line and the address on this origin', async ({ page }) => {
  test.setTimeout(120_000);
  await page.route(`**${SLACK}`, async (route) => {
    if (route.request().method() !== 'GET') {
      await route.fallback();
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ state: 'on', path: '/ocutalon/hook/slack/events', links: [{ ref: 'zzSlackRef000000000001', user: 'sam', member: 'U012AB3CDE' }], users: ['sam', 'pat'] }),
    });
  });
  const group = await openSlack(page);
  await expect(group.getByText('Slack on', { exact: true }), 'the state line').toBeVisible();
  const origin = await page.evaluate(() => window.location.origin);
  await expect(group.locator('[data-slack="address"]'), 'the address on this page\'s origin').toHaveText(`Subscribe your Slack app's events to ${origin}/ocutalon/hook/slack/events.`);
  await expect(group.getByText(NOT_SET_UP, { exact: true }), 'no not-set-up line').toHaveCount(0);
  await expect(group.getByRole('group', { name: 'sam', exact: true }), 'the listed member').toContainText('U012AB3CDE');
  await expect(group.getByLabel('OcuTalon user', { exact: true }).locator('option'), 'the picker offers the listed users').toHaveText(['sam', 'pat']);
});

test('SS6: a list that fails to load shows the load error with Retry, and Retry loads the group', async ({ page }) => {
  test.setTimeout(120_000);
  let failing = true;
  await page.route(`**${SLACK}`, async (route) => {
    if (route.request().method() === 'GET' && failing) {
      await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) });
    } else {
      await route.fallback();
    }
  });
  await recordAnnouncements(page);
  const group = await openSlack(page);
  await expect(group.getByText(LOAD_FAILED, { exact: true }), 'the group shows the load error').toBeVisible();
  await expect.poll(() => announcements(page, LOAD_FAILED), 'and the announcer reads it once').toBe(1);
  await expect(group.getByRole('button', { name: 'Retry', exact: true }), 'with Retry').toBeVisible();
  await expect(group.getByRole('button', { name: 'Link member', exact: true }), 'in place of the form').toHaveCount(0);
  failing = false;
  await group.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(group.getByRole('button', { name: 'Link member', exact: true }), 'Retry loads the form').toBeVisible();
  await expect(group.getByText(LOAD_FAILED, { exact: true }), 'and the load error is gone').toHaveCount(0);
});
