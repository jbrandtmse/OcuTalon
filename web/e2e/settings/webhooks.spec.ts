import { expect, test, type Locator, type Page } from '../support/fixtures';


import { signInReadmeLoaded } from '../support/floor';
import { chk, irisScript, quoted } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 35.3, the Webhooks group of Settings > Channels in a real browser, signed in as the README admin (WS1 and WS2; the sign-in-2 unit):
 *   WS1  the admin creates a webhook from the page: the saved line shows, the form empties, the webhook is listed in a group of its own with the address line
 *        (this page's origin and the webhook's path), its secret field is empty (write-only, a password field) with the hint, and no text of the page holds the
 *        secret; the refused values show their texts under their fields (a setting reference, a short secret, a name already used), and nothing is stored; a
 *        replaced secret shows the saved line and empties the field, and the row then holds the new secret and not the old;
 *   WS2  an online-demo answer (409 not_available, fulfilled by the test) shows the ruled text in place of the form;
 *   WS3  a 403 shows the denied text in the group, and a failed create shows the form error under the button;
 *   WS4  a list that fails to load (500, fulfilled by the test) shows the accepted load error with Retry in place of the form, announced once, and Retry then
 *        loads the form.
 * The texts are written out here as the oracle. Every case removes its `zz` webhooks.
 */
const SETTINGS = '/ocutalon/api/v1/settings/channels/webhooks';
const SAVED = 'Saved. Applies within a minute. Recorded in the audit log.';
const HINT = 'Saved, and never shown again. Type a new value to replace it.';
const EXPANSION = "This can't contain @{, which IRIS would read as a reference to a setting. Nothing was changed.";
const BAD_SECRET = 'Use a secret of 16 to 256 characters: letters, digits and punctuation, with no spaces. Nothing was changed.';
const OFF = 'Webhooks are off on the online demo, so it has no public webhook address. They work on your own install.';
const LOAD_FAILED = "Couldn't load your session.";
const HELP = 'Other systems can send OcuTalon any JSON event. Each webhook has its own secret, which the sender puts in the X-OcuTalon-Webhook-Secret header.';

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });

/** Signs the README admin in and opens Settings > Channels; returns the Webhooks group. */
async function openWebhooks(page: Page): Promise<Locator> {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Channels', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Channels' })).toBeVisible();
  return page.getByRole('region', { name: 'Webhooks', exact: true });
}

/** Removes the admin's webhooks whose names start with the prefix (rows and counters). */
async function dropByPrefix(page: Page, prefix: string): Promise<void> {
  const list = (await (await page.request.get(SETTINGS)).json()) as { webhooks?: Array<{ ref: string; name: string }> };
  const refs = (list.webhooks ?? []).filter((one) => one.name.startsWith(prefix)).map((one) => one.ref);
  const lines = refs.map(
    (ref) => `Set w=##class(OcuTalon.Data.Webhook).RefIndexOpen(${quoted(ref)}) If $IsObject(w) { Set id=w.%Id() Kill w Do ##class(OcuTalon.Data.Webhook).%DeleteId(id) } Kill ^OcuTalonP.WebhookC("a",${quoted(ref)}),^OcuTalonP.WebhookC("r",${quoted(ref)})`,
  );
  await irisScript([...lines, 'Write !,"CHK|dropped|1"'].join('\n'));
}

test('WS1: an admin creates a webhook from the page, sees its address, and replaces its secret', async ({ page }) => {
  test.setTimeout(180_000);
  const stamp = Date.now().toString(36);
  const name = `zz-ws1-${stamp}`;
  const secret = `zz-page-secret-${stamp}-0123456789`;
  const replacement = `zz-page-replaced-${stamp}-9876543210`;
  try {
    const group = await openWebhooks(page);
    await expect(group.getByRole('heading', { level: 3, name: 'Webhooks' })).toBeVisible();
    await expect(group.getByText(HELP, { exact: true }), 'the help line').toBeVisible();
    await expect(group.getByLabel('Name', { exact: true }), 'the name field').toBeVisible();
    const secretField = group.locator('#webhook-secret');
    await expect(secretField, 'the secret field is write-only').toHaveAttribute('type', 'password');

    // The refused values, each under its field, and nothing stored.
    await group.locator('#webhook-name').fill(`${name} @{x}`);
    await secretField.fill(secret);
    await group.getByRole('button', { name: 'Create webhook', exact: true }).click();
    await expect(group.locator('#webhook-name-error'), 'a setting reference in the name').toHaveText(EXPANSION);
    await expect(group.locator('#webhook-name'), 'takes focus').toBeFocused();
    await group.locator('#webhook-name').fill(name);
    await expect(group.locator('#webhook-name-error'), 'typing clears the error').toHaveCount(0);
    await secretField.fill('short');
    await group.getByRole('button', { name: 'Create webhook', exact: true }).click();
    await expect(group.locator('#webhook-secret-error'), 'a short secret').toHaveText(BAD_SECRET);
    await expect(secretField, 'takes focus').toBeFocused();
    expect((await (await page.request.get(SETTINGS)).json()) as { webhooks: unknown[] }, 'nothing was stored').toMatchObject({ webhooks: expect.not.arrayContaining([expect.objectContaining({ name })]) });

    // The create.
    await secretField.fill(secret);
    await group.getByRole('button', { name: 'Create webhook', exact: true }).click();
    await expect(group.locator('p.saved[data-saved="create"]'), 'the saved line').toHaveText(SAVED);
    await expect(group.locator('#webhook-name'), 'the form is emptied').toHaveValue('');
    await expect(secretField, 'including the secret field').toHaveValue('');
    const row = group.getByRole('group', { name, exact: true });
    await expect(row, 'the webhook is listed in a group of its own').toBeVisible();
    const list = (await (await page.request.get(SETTINGS)).json()) as { webhooks: Array<{ ref: string; name: string; path: string }> };
    const made = list.webhooks.find((one) => one.name === name);
    expect(made, 'the server lists it').toBeTruthy();
    const origin = new URL(page.url()).origin;
    await expect(row.getByText(`Send events with POST to ${origin}${made?.path}.`, { exact: true }), 'with its address').toBeVisible();
    const rowSecret = row.locator('input[type="password"]');
    await expect(rowSecret, 'its secret field is empty').toHaveValue('');
    await expect(row.getByText(HINT, { exact: true }), 'with the hint that it is never shown again').toBeVisible();
    expect(await page.locator('body').innerText(), 'no text of the page holds the secret').not.toContain(secret);
    expect(await page.content(), 'nor does its markup').not.toContain(secret);

    // The same name in another case is refused under the name field.
    await group.locator('#webhook-name').fill(name.toUpperCase());
    await secretField.fill(secret);
    await group.getByRole('button', { name: 'Create webhook', exact: true }).click();
    await expect(group.locator('#webhook-name-error'), 'a name already used').toHaveText(`A webhook called '${name.toUpperCase()}' already exists. Nothing was changed.`);

    // The replacement.
    await rowSecret.fill(replacement);
    await row.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(row.locator('p.saved[data-saved="rotate"]'), 'the saved line under the webhook').toHaveText(SAVED);
    await expect(rowSecret, 'its secret field is emptied').toHaveValue('');
    const check = await irisScript(
      [
        `Set w=##class(OcuTalon.Data.Webhook).RefIndexOpen(${quoted(made?.ref ?? '')})`,
        `Write !,"CHK|old|",##class(OcuTalon.Data.Webhook).Matches(w.SecretHash,${quoted(secret)})`,
        `Write !,"CHK|new|",##class(OcuTalon.Data.Webhook).Matches(w.SecretHash,${quoted(replacement)})`,
      ].join('\n'),
    );
    expect([chk(check, 'old'), chk(check, 'new')], 'the row holds the new secret and not the old').toEqual(['0', '1']);
    await rowSecret.fill('short');
    await row.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(row.locator('[id^="webhook-secret-error-"]'), 'a short replacement is refused under its field').toHaveText(BAD_SECRET);
  } finally {
    await dropByPrefix(page, 'zz-ws1-');
  }
});

test('WS2: an online-demo answer shows the ruled text in place of the form', async ({ page }) => {
  test.setTimeout(120_000);
  await page.route('**/api/v1/settings/channels/webhooks', async (route) => {
    await route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_available', message: OFF } }) });
  });
  const group = await openWebhooks(page);
  await expect(group.getByText(OFF, { exact: true }), 'the group says that webhooks are off').toBeVisible();
  await expect(group.getByRole('button', { name: 'Create webhook', exact: true }), 'there is no form').toHaveCount(0);
  await expect(group.getByRole('textbox'), 'and no field').toHaveCount(0);
  await expect(group.getByText(HELP, { exact: true }), 'and no help for the form').toHaveCount(0);
});

test('WS3: a 403 shows the denied text in the group, and a failed create shows the form error under the button', async ({ page }) => {
  test.setTimeout(120_000);
  let mode: 'ok' | 'fail' | 'denied' = 'ok';
  await page.route('**/api/v1/settings/channels/webhooks', async (route) => {
    if (route.request().method() === 'POST' && mode === 'fail') {
      await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) });
    } else if (route.request().method() === 'POST' && mode === 'denied') {
      await route.fulfill({ status: 403, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_admin', message: 'x' } }) });
    } else {
      await route.fallback();
    }
  });
  const group = await openWebhooks(page);
  await group.locator('#webhook-name').fill('zz-ws3');
  await group.locator('#webhook-secret').fill('zz-ws3-secret-0123456789');
  mode = 'fail';
  await group.getByRole('button', { name: 'Create webhook', exact: true }).click();
  await expect(group.locator('#webhook-form-error'), 'a failed create').toHaveText("Couldn't save. Nothing was changed.");
  mode = 'denied';
  await group.getByRole('button', { name: 'Create webhook', exact: true }).click();
  await expect(group.getByText('Only OcuTalon admins can open settings.', { exact: true }), 'a 403 shows the denied text in the group').toBeVisible();
  await expect(group.getByRole('button', { name: 'Create webhook', exact: true }), 'in place of the form').toHaveCount(0);
  const stored = await irisScript('Write !,"CHK|n|",##class(OcuTalon.Data.Webhook).NameTaken("zz-ws3")');
  expect(chk(stored, 'n'), 'nothing was stored').toBe('0');
});

test('WS4: a list that fails to load shows the load error with Retry in place of the form, and Retry loads it', async ({ page }) => {
  test.setTimeout(120_000);
  let failing = true;
  await page.route('**/api/v1/settings/channels/webhooks', async (route) => {
    if (route.request().method() === 'GET' && failing) {
      await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'x' } }) });
    } else {
      await route.fallback();
    }
  });
  await recordAnnouncements(page);
  const group = await openWebhooks(page);
  await expect(group.getByText(LOAD_FAILED, { exact: true }), 'the group shows the load error').toBeVisible();
  await expect.poll(() => announcements(page, LOAD_FAILED), 'and the announcer reads it once').toBe(1);
  await expect(group.getByRole('button', { name: 'Retry', exact: true }), 'with Retry').toBeVisible();
  await expect(group.getByRole('button', { name: 'Create webhook', exact: true }), 'in place of the form').toHaveCount(0);
  await expect(group.getByRole('textbox'), 'with no field').toHaveCount(0);
  await expect(group.getByText(HELP, { exact: true }), 'and no help for the form').toHaveCount(0);
  failing = false;
  await group.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(group.getByRole('button', { name: 'Create webhook', exact: true }), 'Retry loads the form').toBeVisible();
  await expect(group.getByText(LOAD_FAILED, { exact: true }), 'and the load error is gone').toHaveCount(0);
});
