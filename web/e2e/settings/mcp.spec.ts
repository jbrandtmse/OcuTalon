import { expect, test, type Locator, type Page } from '../support/fixtures';

import { envelope } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';
import { approvalState, clearChangedTool, dropMcpServer, leftovers, seedMcpServer } from '../support/mcp';

/**
 * Story 21.4, Settings > Tools and MCP servers in a real browser, signed in as the README admin (B1 to B6; the sign-in-2 unit). The servers of B1, B3 and B4 are
 * fixture rows made with irisScript (a server row, its tool rows and, for B4, a pending `tool_call` approval row whose ToolSource is the server's toolref), and
 * B2 adds a server through the form (at a loopback address nothing listens on; it has no tools). Every case removes its `zz` servers, tools, approval rows, entries
 * and wallet keys in `finally`.
 *   B1  the section lists a fixture server with its status, tool and unclassified counts, and its tools; "Unclassified only" filters the tools, and turning it off
 *       again leaves each tool's radiogroup with its own classification checked;
 *   B2  the add form shows the field errors under their fields (the first takes focus), and a good add shows the server's message, empties the fields (the secret
 *       field is a password field and no text of the page holds the secret) and lists the server with its address;
 *   B3  a pick in a tool's radiogroup shows the check icon and "Saved" at once, and survives a reload;
 *   B4  the Remove dialog says "Remove {server}? Its 12 tools go at once, and 1 pending approval request for them is cancelled."; Cancel keeps the server; Remove
 *       takes it and its tools off the lists and leaves the pending fixture row canceled;
 *   B5  a 409 not_available (fulfilled by the test) shows the online demo's line in place of the content;
 *   B6  a pick whose save fails (a 500 fulfilled by the test) puts the old value back and shows the server's message in the row;
 *   B7  a 403 on the list (fulfilled by the test) shows the page's denied text in place of the content (QA);
 *   B8  a 500 on the list shows the load error with Retry, and Retry loads the list again and shows the content (QA);
 *   B9  an add answered 500 shows the server's message under the button, keeps what was typed and loads the list again (QA);
 *   B10 a removal answered 500 leaves the dialog open with the server's message and the server listed; a 404 closes it and the server and its tools leave the lists (QA).
 *   B11 (Story 21.5) a Read-only tool's "Use as a source" opens the form, and a risky tool's is aria-disabled with the reason beside it; saving "Jira{tag}" shows "Saved", closes the
 *       form, and lists the source under "Your sources" ("Jira{tag} | zz_lookup on {server} | 15 minutes"); its Remove takes the row off and the Saved line; a pick of Read-only
 *       for the risky tool makes its control choosable at once;
 *   B12 arguments that are not a JSON object show the accepted error under Arguments (JSON), and focus moves there.
 *   B13 the source form's failed save (500) and a refused tool show form-level; a refused name and interval show under their fields with focus on the first; a 403 and a 409 on a save and
 *       on a Remove show the denied and demo states; a later good save clears a failed Remove's message; a 404 on a Remove shows the server's message and the list loses the
 *       source; Cancel returns focus to the opening tool's button and the next form starts empty.
 *   B14 (Story 21.9) a tool that Lane A's ClearChanged made Unclassified has one warning banner above the tools table, in the words of settings.toolChangedBanner, and
 *       its radiogroup shows Unclassified; a new tool and a changed tool that is refused have none; a pick whose save fails keeps the banner; a pick that saves
 *       shows "Saved" and the banner goes, and stays gone after a reload; a second changed tool has its own banner after the first, in table order, and the pick
 *       takes away only the banner of the tool it classified (QA).
 * B7 to B10 fulfil every answer of the MCP routes themselves (no fixture server, no IRIS fixture), so they cover the section's states and nothing of the server.
 * The texts are written out here as the oracle.
 */
const MCP = '/ocutalon/api/v1/settings/mcp';
const ADDED = 'The MCP server was added. Its tools count as risky until an admin classifies them.';
const BAD_ADDRESS = "An MCP server's address must start with https:// (or point to this computer, for development). Nothing was changed.";
const BAD_NAME = "An MCP server's name is a letter followed by up to 39 letters, digits or underscores. Nothing was changed.";
const BAD_SECRET = 'Use a secret of up to 4,096 letters, digits and punctuation, with no spaces. Nothing was changed.';
const OFF = 'MCP servers are off on the online demo: nobody can add one, and OcuTalon reaches none. They work on your own install.';
const STATUS_HELP = "A new server's tools show here once OcuTalon next uses its agents. They count as risky until you classify them.";

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const sectionsNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Settings sections', exact: true });

/** A unique tag for the case's names (letters and digits only). */
const tag = (): string => `${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;

/** Signs the README admin in and opens Settings > Tools and MCP servers once it has loaded. */
async function openMcp(page: Page): Promise<void> {
  await signInReadmeLoaded(page);
  await pagesNav(page).getByRole('link', { name: 'Settings', exact: true }).click();
  await sectionsNav(page).getByRole('link', { name: 'Tools and MCP servers', exact: true }).click();
  await expect(page.getByRole('heading', { level: 2, name: 'Tools and MCP servers' })).toBeVisible();
}

const servers = (page: Page): Locator => page.getByRole('region', { name: 'Servers', exact: true });
const tools = (page: Page): Locator => page.getByRole('region', { name: 'Tools', exact: true });

test('B1: the section lists a server and its tools, and Unclassified only filters them', async ({ page }) => {
  test.setTimeout(180_000);
  const name = `zzb1${tag()}`;
  try {
    await seedMcpServer(name, [{ name: 'zz_open' }, { name: 'zz_aread', classification: 'read-only' }, { name: 'zz_risky', classification: 'risky' }]);
    await openMcp(page);
    const row = servers(page).locator(`tr[data-server="${name}"]`);
    await expect(row, 'the server is listed').toBeVisible();
    await expect(row.getByRole('rowheader'), 'with its name').toHaveText(name);
    await expect(row.getByRole('cell').nth(1), 'its status').toHaveText('Connected');
    await expect(row.getByRole('cell').nth(2), 'its tool count').toHaveText('3');
    await expect(row.getByRole('cell').nth(3), 'its unclassified count').toHaveText('1');
    await expect(servers(page).getByText(STATUS_HELP, { exact: true }), 'the help line').toBeVisible();
    await expect(servers(page).getByRole('columnheader'), 'the headers').toHaveText(['Server', 'Address', 'Status', 'Tools', 'Unclassified']);

    const mine = tools(page).locator(`tr[data-server="${name}"]`);
    await expect(mine, 'its three tools').toHaveCount(3);
    await expect(tools(page).getByRole('columnheader'), 'the tools headers').toHaveText(['Tool', 'Server', 'Status', 'Classification', 'Source']);
    const open = tools(page).locator(`tr[data-tool="zz_open"][data-server="${name}"]`);
    await expect(open.getByRole('cell').nth(1), 'a tool\'s status').toHaveText('Available');
    const group = open.getByRole('radiogroup', { name: `Classification of zz_open on ${name}`, exact: true });
    await expect(group.getByRole('radio'), 'three radios').toHaveCount(3);
    await expect(group.getByRole('radio', { name: 'Unclassified (counts as risky)', exact: true }), 'the unclassified tool is checked as such').toBeChecked();

    await tools(page).getByRole('checkbox', { name: 'Unclassified only', exact: true }).check();
    await expect(mine, 'the filter keeps only the unclassified tool of the server').toHaveCount(1);
    await expect(open).toBeVisible();
    await tools(page).getByRole('checkbox', { name: 'Unclassified only', exact: true }).uncheck();
    await expect(mine, 'and off lists all three again').toHaveCount(3);
    // zz_aread sorts before zz_open, so turning the filter off puts a row in front of zz_open: each row's radiogroup keeps its own checked radio.
    const checkedOf = (tool: string, label: string): Locator =>
      tools(page).locator(`tr[data-tool="${tool}"][data-server="${name}"]`).getByRole('radio', { name: label, exact: true });
    await expect(checkedOf('zz_aread', 'Read-only'), 'the read-only tool is checked as such').toBeChecked();
    await expect(checkedOf('zz_open', 'Unclassified (counts as risky)'), 'the unclassified tool is still checked as such').toBeChecked();
    await expect(checkedOf('zz_risky', 'Risky'), 'and the risky one as such').toBeChecked();
  } finally {
    await dropMcpServer(name);
  }
});

test('B2: the add form shows its field errors, and a good add lists the server', async ({ page }) => {
  test.setTimeout(240_000);
  const name = `zzb2${tag()}`;
  const secret = `zz-form-secret-${tag()}-0123456789`;
  try {
    await openMcp(page);
    const form = servers(page).getByRole('group', { name: 'Add server', exact: true });
    await expect(form.locator('#mcp-secret'), 'the secret field is write-only').toHaveAttribute('type', 'password');
    await expect(form.getByText('Sent to the server with every request. It is kept in the IRIS Wallet and never shown again.', { exact: true }), 'with its help').toBeVisible();

    // The refusals: the first field in error takes focus, and typing clears its error.
    await form.locator('#mcp-name').fill('1 bad');
    await form.locator('#mcp-address').fill('http://example.invalid/mcp');
    await form.locator('#mcp-secret').fill('zz secret');
    await form.getByRole('button', { name: 'Add server', exact: true }).click();
    await expect(form.locator('#mcp-name-error'), 'a bad name').toHaveText(BAD_NAME);
    await expect(form.locator('#mcp-address-error'), 'a non-loopback http address').toHaveText(BAD_ADDRESS);
    await expect(form.locator('#mcp-secret-error'), 'a secret with a space').toHaveText(BAD_SECRET);
    await expect(form.locator('#mcp-name'), 'the first takes focus').toBeFocused();
    await form.locator('#mcp-name').fill(name);
    await expect(form.locator('#mcp-name-error'), 'typing clears its error').toHaveCount(0);
    await form.getByRole('button', { name: 'Add server', exact: true }).click();
    await expect(form.locator('#mcp-address-error'), 'the address is still refused').toHaveText(BAD_ADDRESS);
    await expect(form.locator('#mcp-address'), 'and takes focus').toBeFocused();
    expect((await leftovers(name)).row, 'nothing was made').toBe(0);

    // The add.
    await form.locator('#mcp-address').fill('https://127.0.0.1:1/mcp');
    await form.locator('#mcp-secret').fill(secret);
    await form.getByRole('button', { name: 'Add server', exact: true }).click();
    await expect(form.locator('p.saved[data-saved="add"]'), 'the server\'s message').toHaveText(ADDED);
    await expect(form.locator('#mcp-name'), 'the name is emptied').toHaveValue('');
    await expect(form.locator('#mcp-address'), 'and the address').toHaveValue('');
    await expect(form.locator('#mcp-secret'), 'and the secret').toHaveValue('');
    await expect(servers(page).locator(`tr[data-server="${name}"]`), 'the server is listed').toBeVisible();
    await expect(servers(page).locator(`tr[data-server="${name}"]`).getByRole('cell').nth(0), 'with its address').toHaveText('https://127.0.0.1:1/mcp');
    await expect(servers(page).locator(`tr[data-server="${name}"]`).getByRole('cell').nth(1), 'never checked yet').toHaveText('Not checked yet');
    expect(await page.locator('body').innerText(), 'no text of the page holds the secret').not.toContain(secret);
    expect(await page.content(), 'nor does its markup').not.toContain(secret);
    expect(await leftovers(name), 'the row, entry, key and collection are made').toMatchObject({ row: 1, entry: 1, key: 1, collection: 1 });
  } finally {
    await page.request.delete(`${MCP}/servers/${name}`, { headers: envelope(), data: {} }).catch(() => undefined);
    await dropMcpServer(name);
  }
});

test('B3: a radiogroup pick shows the check icon and Saved, and survives a reload', async ({ page }) => {
  test.setTimeout(180_000);
  const name = `zzb3${tag()}`;
  try {
    await seedMcpServer(name, [{ name: 'zz_pick' }]);
    await openMcp(page);
    const row = tools(page).locator(`tr[data-tool="zz_pick"][data-server="${name}"]`);
    const group = row.getByRole('radiogroup', { name: `Classification of zz_pick on ${name}`, exact: true });
    await expect(group).toBeVisible();
    await expect(group.locator('app-icon'), 'only the checked option shows the check icon').toHaveCount(1);
    await group.getByRole('radio', { name: 'Read-only', exact: true }).check();
    await expect(row.locator('p.saved[data-saved="classify"]'), 'Saved shows for the row').toHaveText('Saved');
    await expect(group.getByRole('radio', { name: 'Read-only', exact: true })).toBeChecked();
    await expect(group.locator('label', { hasText: 'Read-only' }).locator('app-icon'), 'the check icon is on the picked option').toHaveCount(1);
    await expect(group.locator('app-icon'), 'and only there').toHaveCount(1);
    await expect(servers(page).locator(`tr[data-server="${name}"]`).getByRole('cell').nth(3), 'the unclassified count follows').toHaveText('0');

    await page.reload();
    await expect(page.getByRole('heading', { level: 2, name: 'Tools and MCP servers' })).toBeVisible();
    const again = tools(page).locator(`tr[data-tool="zz_pick"][data-server="${name}"]`).getByRole('radiogroup', { name: `Classification of zz_pick on ${name}`, exact: true });
    await expect(again.getByRole('radio', { name: 'Read-only', exact: true }), 'the pick survives a reload').toBeChecked();
  } finally {
    await dropMcpServer(name);
  }
});

test('B4: the Remove dialog names the counts, Cancel keeps the server, and Remove takes it and cancels its pending request', async ({ page }) => {
  test.setTimeout(240_000);
  const name = `ZzJira${tag()}`;
  let refs: string[] = [];
  try {
    refs = await seedMcpServer(
      name,
      Array.from({ length: 12 }, (_, index) => ({ name: `zz_tool_${String(index + 1).padStart(2, '0')}` })),
      1,
    );
    expect(refs, 'one pending fixture request').toHaveLength(1);
    expect(await approvalState(refs[0] ?? ''), 'it is pending').toBe('pending');
    await openMcp(page);
    const row = servers(page).locator(`tr[data-server="${name}"]`);
    await expect(row.getByRole('cell').nth(2), 'twelve tools').toHaveText('12');
    const sentence = `Remove ${name}? Its 12 tools go at once, and 1 pending approval request for them is cancelled.`;

    const remove = row.getByRole('button', { name: `Remove ${name}`, exact: true });
    await remove.click();
    const dialog = page.getByRole('dialog', { name: sentence, exact: true });
    await expect(dialog, 'the dialog is named by its sentence').toBeVisible();
    await expect(dialog.getByRole('heading', { name: sentence, exact: true }), 'and the sentence takes the first focus').toBeFocused();
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(dialog).toHaveCount(0);
    await expect(remove, 'focus returns to the button').toBeFocused();
    await expect(row, 'Cancel keeps the server').toBeVisible();
    expect(await approvalState(refs[0] ?? ''), 'and its pending request').toBe('pending');

    await remove.click();
    await page.getByRole('dialog', { name: sentence, exact: true }).getByRole('button', { name: 'Remove', exact: true }).click();
    await expect(page.getByRole('dialog'), 'the dialog closes').toHaveCount(0);
    await expect(row, 'the server leaves the list').toHaveCount(0);
    await expect(tools(page).locator(`tr[data-server="${name}"]`), 'and its tools leave the table').toHaveCount(0);
    expect(await approvalState(refs[0] ?? ''), 'the pending request is canceled').toBe('cancelled');
    expect(await leftovers(name), 'nothing of the server is left').toMatchObject({ row: 0, tools: 0, entry: 0, key: 0, collection: 0 });
  } finally {
    await dropMcpServer(name, refs);
  }
});

test('B5: a 409 not_available shows the online demo\'s line in place of the content', async ({ page }) => {
  test.setTimeout(120_000);
  await page.route(`**${MCP}`, async (route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_available', message: OFF } }) });
    } else {
      await route.fallback();
    }
  });
  await openMcp(page);
  await expect(page.getByText(OFF, { exact: true }), 'the section says that MCP servers are off').toBeVisible();
  await expect(page.getByRole('button', { name: 'Add server', exact: true }), 'there is no form').toHaveCount(0);
  await expect(page.getByRole('textbox'), 'and no field').toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Servers', exact: true }), 'and no group').toHaveCount(0);
});

test('B6: a pick whose save fails puts the old value back and shows the message', async ({ page }) => {
  test.setTimeout(180_000);
  const name = `zzb6${tag()}`;
  const FAILED = 'Something went wrong inside OcuTalon. Try again.';
  try {
    await seedMcpServer(name, [{ name: 'zz_fail' }]);
    await page.route(`**${MCP}/classify`, async (route) => {
      await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: FAILED } }) });
    });
    await openMcp(page);
    const row = tools(page).locator(`tr[data-tool="zz_fail"][data-server="${name}"]`);
    const group = row.getByRole('radiogroup', { name: `Classification of zz_fail on ${name}`, exact: true });
    await expect(group.getByRole('radio', { name: 'Unclassified (counts as risky)', exact: true })).toBeChecked();
    await group.getByRole('radio', { name: 'Read-only', exact: true }).click();
    await expect(row.getByText(FAILED, { exact: true }), 'the server\'s message shows in the row').toBeVisible();
    await expect(group.getByRole('radio', { name: 'Unclassified (counts as risky)', exact: true }), 'the old value is back').toBeChecked();
    await expect(group.getByRole('radio', { name: 'Read-only', exact: true }), 'and the pick is not kept').not.toBeChecked();
    await expect(row.locator('p.saved[data-saved="classify"]'), 'with no Saved').toHaveCount(0);
    await expect(servers(page).locator(`tr[data-server="${name}"]`).getByRole('cell').nth(3), 'the unclassified count is back too').toHaveText('1');
  } finally {
    await dropMcpServer(name);
  }
});

/** A list answer of the MCP settings route, as the section reads it. */
const listBody = (servers: Array<{ name: string; tools: number; pending: number }>): string =>
  JSON.stringify({
    servers: servers.map((one) => ({ name: one.name, address: 'https://127.0.0.1:1/mcp', status: 'attached', tools: one.tools, unclassified: one.tools, pending: one.pending })),
    tools: servers.flatMap((one) =>
      Array.from({ length: one.tools }, (_, index) => ({ server: one.name, name: `zz_tool_${index + 1}`, classification: 'unclassified', status: 'available' })),
    ),
  });

const SERVER_FAILED = 'Something went wrong inside OcuTalon. Try again.';
const failure = { status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: SERVER_FAILED } }) } as const;

test('B7: a 403 on the list shows the denied text in place of the content', async ({ page }) => {
  test.setTimeout(120_000);
  await page.route(`**${MCP}`, async (route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({ status: 403, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_admin', message: 'Only OcuTalon admins can open settings.' } }) });
    } else {
      await route.fallback();
    }
  });
  await openMcp(page);
  await expect(page.locator('[data-state="denied"]'), 'the denied state shows').toHaveText('Only OcuTalon admins can open settings.');
  await expect(page.getByRole('button', { name: 'Add server', exact: true }), 'there is no form').toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Servers', exact: true }), 'and no group').toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Retry', exact: true }), 'and no Retry (a refusal is not a failure to load)').toHaveCount(0);
});

test('B8: a 500 on the list shows the load error with Retry, and Retry loads the list', async ({ page }) => {
  test.setTimeout(120_000);
  let gets = 0;
  await page.route(`**${MCP}`, async (route) => {
    if (route.request().method() !== 'GET') {
      await route.fallback();
    } else if (gets++ === 0) {
      await route.fulfill(failure);
    } else {
      await route.fulfill({ status: 200, contentType: 'application/json', body: listBody([{ name: 'zzb8', tools: 1, pending: 0 }]) });
    }
  });
  await openMcp(page);
  const failed = page.locator('[data-state="failed"]');
  await expect(failed.getByText("Couldn't load your session.", { exact: true }), 'the load error shows').toBeVisible();
  await expect(page.getByRole('region', { name: 'Servers', exact: true }), 'in place of the content').toHaveCount(0);
  await failed.getByRole('button', { name: 'Retry', exact: true }).click();
  await expect(servers(page).locator('tr[data-server="zzb8"]'), 'Retry loads the list').toBeVisible();
  await expect(page.locator('[data-state="failed"]'), 'and the load error is gone').toHaveCount(0);
  expect(gets, 'the list was asked for twice').toBe(2);
});

test('B9: an add answered 500 shows the message, keeps what was typed and loads the list again', async ({ page }) => {
  test.setTimeout(120_000);
  let gets = 0;
  await page.route(`**${MCP}`, async (route) => {
    if (route.request().method() !== 'GET') {
      await route.fallback();
      return;
    }
    gets += 1;
    await route.fulfill({ status: 200, contentType: 'application/json', body: listBody(gets === 1 ? [] : [{ name: 'zzb9', tools: 0, pending: 0 }]) });
  });
  await page.route(`**${MCP}/servers`, async (route) => {
    if (route.request().method() === 'POST') {
      await route.fulfill(failure);
    } else {
      await route.fallback();
    }
  });
  await openMcp(page);
  const form = servers(page).getByRole('group', { name: 'Add server', exact: true });
  await expect(servers(page).locator('tr[data-server="zzb9"]'), 'the first list holds no server').toHaveCount(0);
  await form.locator('#mcp-name').fill('zzb9');
  await form.locator('#mcp-address').fill('https://127.0.0.1:1/mcp');
  await form.getByRole('button', { name: 'Add server', exact: true }).click();
  await expect(form.locator('#mcp-add-error'), 'the server\'s message shows under the button').toHaveText(SERVER_FAILED);
  await expect(form.locator('#mcp-name'), 'the name that was typed is kept').toHaveValue('zzb9');
  await expect(form.locator('#mcp-address'), 'and the address').toHaveValue('https://127.0.0.1:1/mcp');
  await expect(form.locator('p.saved[data-saved="add"]'), 'with no success line').toHaveCount(0);
  await expect(servers(page).locator('tr[data-server="zzb9"]'), 'the list is loaded again (the add may have been carried out)').toBeVisible();
  expect(gets, 'the list was asked for twice').toBe(2);
});

test('B10: a removal answered 500 leaves the dialog open with the message, and a 404 closes it and takes the server off the lists', async ({ page }) => {
  test.setTimeout(120_000);
  let gone = false;
  let deletes = 0;
  await page.route(`**${MCP}`, async (route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({ status: 200, contentType: 'application/json', body: listBody(gone ? [] : [{ name: 'zzb10', tools: 2, pending: 0 }]) });
    } else {
      await route.fallback();
    }
  });
  await page.route(`**${MCP}/servers/zzb10`, async (route) => {
    deletes += 1;
    if (deletes === 1) {
      await route.fulfill(failure);
    } else {
      gone = true;
      await route.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ error: { code: 'not_found', message: 'That was not found.' } }) });
    }
  });
  await openMcp(page);
  // CSS locators: while the dialog is open, the page behind it is hidden from the accessibility tree, so a role-based region would not find the row.
  const row = page.locator('[data-group="servers"] tr[data-server="zzb10"]');
  const toolRows = page.locator('[data-group="tools"] tr[data-server="zzb10"]');
  await expect(toolRows, 'its two tools are listed').toHaveCount(2);
  await row.getByRole('button', { name: 'Remove zzb10', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Remove zzb10? Its 2 tools go at once.', exact: true });
  await expect(dialog, 'the dialog says what goes').toBeVisible();
  await dialog.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(dialog.getByText(SERVER_FAILED, { exact: true }), 'a 500 shows the server\'s message in the dialog').toBeVisible();
  await expect(dialog, 'and leaves it open').toBeVisible();
  await expect(row, 'with the server still listed').toBeVisible();
  await dialog.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(page.getByRole('dialog'), 'a 404 closes the dialog (the server is gone either way)').toHaveCount(0);
  await expect(row, 'the server leaves the list').toHaveCount(0);
  await expect(toolRows, 'and its tools leave the table').toHaveCount(0);
  expect(deletes, 'the removal was asked for twice').toBe(2);
});

const sources = (page: Page): Locator => page.getByRole('region', { name: 'Your sources', exact: true });
const NOT_READ_ONLY = 'Only a Read-only tool can be a source.';
const NAME_REFUSED = "A source's name is 1 to 100 characters. Nothing was changed.";
const INTERVAL_REFUSED = 'A source is polled every 5 to 1,440 minutes. Nothing was changed.';
const BAD_ARGUMENTS = 'Enter the arguments as a JSON object. Nothing was changed.';
const NOT_READ_ONLY_REFUSED = 'Only a Read-only tool can be a source. Nothing was changed.';
const NOT_FOUND = 'OcuTalon has nothing at this address.';

test('B11: a Read-only tool becomes a source and is listed and removed; a risky tool cannot be chosen', async ({ page }) => {
  test.setTimeout(240_000);
  const name = `zzb11${tag()}`;
  const source = `Jira${tag()}`;
  try {
    await seedMcpServer(name, [{ name: 'zz_lookup', classification: 'read-only' }, { name: 'zz_delete', classification: 'risky' }]);
    await openMcp(page);

    const risky = tools(page).locator(`tr[data-tool="zz_delete"][data-server="${name}"]`);
    const riskyButton = risky.getByRole('button', { name: `Use zz_delete on ${name} as a source`, exact: true });
    await expect(riskyButton, "a risky tool's control can't be chosen").toHaveAttribute('aria-disabled', 'true');
    await expect(risky.getByText(NOT_READ_ONLY, { exact: true }), 'and the reason shows beside it').toBeVisible();
    await expect(riskyButton, 'which describes it').toHaveAttribute('aria-describedby', /mcp-source-why-\d+/);
    await riskyButton.click({ force: true });
    await expect(tools(page).getByRole('group', { name: 'Use as a source', exact: true }), 'a press opens nothing').toHaveCount(0);

    const lookup = tools(page).locator(`tr[data-tool="zz_lookup"][data-server="${name}"]`);
    const button = lookup.getByRole('button', { name: `Use zz_lookup on ${name} as a source`, exact: true });
    await expect(button).not.toHaveAttribute('aria-disabled', 'true');
    await button.click();
    const form = tools(page).getByRole('group', { name: 'Use as a source', exact: true });
    await expect(form, 'the form opens').toBeVisible();
    await expect(form.getByText(`zz_lookup on ${name}`, { exact: true }), 'for the tool').toBeVisible();
    await expect(form.getByLabel('Source name', { exact: true }), 'focus starts on Source name').toBeFocused();
    await expect(form.getByLabel('Check every', { exact: true }), '15 minutes is the default').toHaveValue('15');
    await form.getByLabel('Source name', { exact: true }).fill(source);
    await form.getByLabel('Arguments (JSON)', { exact: true }).fill('{"q":"mine"}');
    await form.getByRole('button', { name: 'Save changes', exact: true }).click();

    await expect(tools(page).locator('[data-saved="source"]'), 'Saved shows').toHaveText('Saved');
    await expect(form, 'the form closes').toHaveCount(0);
    await expect(button, 'and focus returns to the tool\'s button').toBeFocused();
    const row = sources(page).locator(`tr[data-source="${source}"]`);
    await expect(row, 'the source is listed').toBeVisible();
    await expect(row.getByRole('rowheader'), 'with its name').toHaveText(source);
    await expect(row.getByRole('cell'), 'its tool and its interval').toHaveText([`zz_lookup on ${name}`, '15 minutes', 'Remove']);

    await row.getByRole('button', { name: `Remove the source ${source}`, exact: true }).click();
    await expect(row, 'Remove takes the row off').toHaveCount(0);
    await expect(tools(page).locator('[data-saved="source"]'), 'and the Saved line is gone').toHaveCount(0);
    await expect(page.locator('#mcp-sources-heading'), 'focus lands on the "Your sources" heading').toBeFocused();
    expect((await leftovers(name)).sources, 'no source row is left by the Remove').toBe(0);

    await risky.getByRole('radiogroup', { name: `Classification of zz_delete on ${name}`, exact: true }).getByRole('radio', { name: 'Read-only', exact: true }).check();
    await expect(riskyButton, 'a pick of Read-only makes the control choosable at once').not.toHaveAttribute('aria-disabled', 'true');
    await expect(risky.getByText(NOT_READ_ONLY, { exact: true }), 'and the reason goes').toHaveCount(0);
  } finally {
    await dropMcpServer(name);
  }
});

test('B12: arguments that are not a JSON object show their error under the field, with focus there', async ({ page }) => {
  test.setTimeout(180_000);
  const name = `zzb12${tag()}`;
  const source = `Jira${tag()}`;
  try {
    await seedMcpServer(name, [{ name: 'zz_lookup', classification: 'read-only' }]);
    await openMcp(page);
    await tools(page).locator(`tr[data-tool="zz_lookup"][data-server="${name}"]`).getByRole('button', { name: `Use zz_lookup on ${name} as a source`, exact: true }).click();
    const form = tools(page).getByRole('group', { name: 'Use as a source', exact: true });
    await form.getByLabel('Source name', { exact: true }).fill(source);
    await form.getByLabel('Arguments (JSON)', { exact: true }).fill('[1]');
    await form.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(form.locator('#mcp-source-arguments-error'), 'the accepted error shows under the field').toHaveText(BAD_ARGUMENTS);
    await expect(form.getByLabel('Arguments (JSON)', { exact: true }), 'and the field takes focus').toBeFocused();
    await expect(sources(page).locator(`tr[data-source="${source}"]`), 'no source was made').toHaveCount(0);
    await form.getByLabel('Arguments (JSON)', { exact: true }).fill('{}');
    await expect(form.locator('#mcp-source-arguments-error'), 'typing clears the error').toHaveCount(0);
  } finally {
    await dropMcpServer(name);
  }
});

/** A list answer with one server, two Read-only tools and the given sources of the session. */
const sourceListBody = (rows: Array<{ ref: string; name: string; tool: string }>): string =>
  JSON.stringify({
    servers: [{ name: 'zzb13', address: 'https://127.0.0.1:1/mcp', status: 'attached', tools: 2, unclassified: 0, pending: 0 }],
    tools: ['zz_a', 'zz_b'].map((tool) => ({ server: 'zzb13', name: tool, classification: 'read-only', status: 'available' })),
    sources: rows.map((one) => ({ ref: one.ref, name: one.name, server: 'zzb13', tool: one.tool, intervalMinutes: 15 })),
  });

/** A canned answer of a route the case fulfils itself. */
interface Answer {
  status: number;
  contentType: string;
  body: string;
}

const refused = (status: number, code: string, message: string, fields?: Record<string, string>): Answer => ({
  status,
  contentType: 'application/json',
  body: JSON.stringify({ error: { code, message }, ...(fields === undefined ? {} : { fields }) }),
});

test('B13: the source form shows a failed save, each refused field with focus on the first, the denied and demo states, and Cancel and reopening start clean', async ({ page }) => {
  test.setTimeout(240_000);
  let gone = false;
  let save: Answer = failure;
  let removal: Answer = failure;
  await page.route(`**${MCP}`, async (route) => {
    if (route.request().method() === 'GET') {
      await route.fulfill({ status: 200, contentType: 'application/json', body: sourceListBody(gone ? [] : [{ ref: 'zzsrc13', name: 'Existing', tool: 'zz_b' }]) });
    } else {
      await route.fallback();
    }
  });
  await page.route(`**${MCP}/sources`, async (route) => {
    if (route.request().method() === 'POST') {
      await route.fulfill(save);
    } else {
      await route.fallback();
    }
  });
  await page.route(`**${MCP}/sources/zzsrc13`, async (route) => {
    if (route.request().method() === 'DELETE') {
      // A 404 says the source is already gone: every list asked for after this answer lacks it, and every list asked for before it holds it.
      if (removal.status === 404) {
        gone = true;
      }
      await route.fulfill(removal);
    } else {
      await route.fallback();
    }
  });
  const buttonOf = (tool: string): Locator => tools(page).getByRole('button', { name: `Use ${tool} on zzb13 as a source`, exact: true });
  const formOf = (): Locator => tools(page).getByRole('group', { name: 'Use as a source', exact: true });
  const saveAs = async (name: string): Promise<void> => {
    await formOf().getByLabel('Source name', { exact: true }).fill(name);
    await formOf().getByRole('button', { name: 'Save changes', exact: true }).click();
  };
  const reopen = async (): Promise<void> => {
    await page.reload();
    await expect(page.getByRole('heading', { level: 2, name: 'Tools and MCP servers' })).toBeVisible();
  };

  await openMcp(page);
  await buttonOf('zz_a').click();

  // (a) a 500 shows the server's message form-level, under the buttons, and keeps the form and what was typed.
  await saveAs('Jira');
  const formError = formOf().locator('#mcp-source-error');
  await expect(formError, "the server's message shows form-level").toHaveText(SERVER_FAILED);
  const saveBox = await formOf().getByRole('button', { name: 'Save changes', exact: true }).boundingBox();
  const errorBox = await formError.boundingBox();
  expect(errorBox?.y ?? 0, 'under the buttons').toBeGreaterThan((saveBox?.y ?? Number.POSITIVE_INFINITY) + (saveBox?.height ?? 0) - 1);
  await expect(formOf().getByLabel('Source name', { exact: true }), 'what was typed is kept').toHaveValue('Jira');
  await expect(formOf().locator('#mcp-source-name-error, #mcp-source-arguments-error, #mcp-source-interval-error'), 'and no field shows an error').toHaveCount(0);
  await expect(tools(page).locator('[data-saved="source"]'), 'with no success line').toHaveCount(0);

  // (b) a refused name and a refused interval each show under their own field, and focus goes to the first one.
  save = refused(400, 'bad_source', 'x', { name: NAME_REFUSED });
  await saveAs('Jira');
  await expect(formOf().locator('#mcp-source-name-error'), 'the name error is under Source name').toHaveText(NAME_REFUSED);
  await expect(formOf().locator('#mcp-source-interval-error'), 'and none is under Check every').toHaveCount(0);
  await expect(formOf().getByLabel('Source name', { exact: true }), 'focus goes to Source name').toBeFocused();
  save = refused(400, 'bad_source', 'x', { intervalMinutes: INTERVAL_REFUSED });
  await formOf().getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(formOf().locator('#mcp-source-interval-error'), 'the interval error is under Check every').toHaveText(INTERVAL_REFUSED);
  await expect(formOf().locator('#mcp-source-name-error'), 'and the name error is gone').toHaveCount(0);
  await expect(formOf().getByLabel('Check every', { exact: true }), 'focus goes to Check every').toBeFocused();
  save = refused(400, 'bad_source', 'x', { name: NAME_REFUSED, intervalMinutes: INTERVAL_REFUSED });
  await formOf().getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(formOf().locator('#mcp-source-name-error'), 'both show').toHaveText(NAME_REFUSED);
  await expect(formOf().locator('#mcp-source-interval-error'), 'each under its field').toHaveText(INTERVAL_REFUSED);
  await expect(formOf().getByLabel('Source name', { exact: true }), 'focus goes to the first refused field').toBeFocused();
  save = refused(400, 'bad_source', 'x', { tool: NOT_READ_ONLY_REFUSED });
  await formOf().getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(formError, "a refused tool shows McpOps' message form-level").toHaveText(NOT_READ_ONLY_REFUSED);
  await expect(formOf().locator('#mcp-source-name-error, #mcp-source-arguments-error, #mcp-source-interval-error'), 'and under no field').toHaveCount(0);

  // (e) Cancel returns focus to the opening tool's button, and the next tool's form starts empty.
  await formOf().getByLabel('Arguments (JSON)', { exact: true }).fill('{"q":1}');
  await formOf().getByLabel('Check every', { exact: true }).selectOption('60');
  await formOf().getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(formOf(), 'Cancel closes the form').toHaveCount(0);
  await expect(buttonOf('zz_a'), 'focus returns to the tool that opened it').toBeFocused();
  await buttonOf('zz_b').click();
  await expect(formOf().getByText('zz_b on zzb13', { exact: true }), 'the form is for the second tool').toBeVisible();
  await expect(formOf().getByLabel('Source name', { exact: true }), 'the name starts blank').toHaveValue('');
  await expect(formOf().getByLabel('Arguments (JSON)', { exact: true }), 'the arguments start blank').toHaveValue('');
  await expect(formOf().getByLabel('Check every', { exact: true }), 'the interval starts at 15 minutes').toHaveValue('15');
  await expect(formOf().locator('.field-error'), 'with no error').toHaveCount(0);

  // (c) a 403 or a 409 on the save replaces the section with the denied or the demo state.
  save = refused(403, 'not_admin', 'Only OcuTalon admins can open settings.');
  await saveAs('Jira');
  await expect(page.locator('[data-state="denied"]'), 'a 403 on the save shows the denied state').toHaveText('Only OcuTalon admins can open settings.');
  await expect(formOf(), 'with no form').toHaveCount(0);
  await reopen();
  await buttonOf('zz_a').click();
  save = refused(409, 'not_available', OFF);
  await saveAs('Jira');
  await expect(page.locator('[data-state="off"]'), 'a 409 on the save shows the demo line').toHaveText(OFF);
  await expect(formOf(), 'with no form').toHaveCount(0);

  // (c) the same two answers on a Remove, and a 500 shows the server's message under the sources.
  await reopen();
  const removeButton = (): Locator => sources(page).getByRole('button', { name: 'Remove the source Existing', exact: true });
  removal = refused(500, 'server_error', SERVER_FAILED);
  await removeButton().click();
  await expect(page.locator('[data-error="sources"]'), 'a 500 on a Remove shows the message').toHaveText(SERVER_FAILED);
  await expect(sources(page).locator('tr[data-source="Existing"]'), 'and the source stays listed').toBeVisible();
  save = { status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'saved', message: 'Saved', ref: 'zzsrc14' }) };
  await buttonOf('zz_a').click();
  await saveAs('Jira');
  await expect(tools(page).locator('[data-saved="source"]'), 'a later good save shows Saved').toHaveText('Saved');
  await expect(page.locator('[data-error="sources"]'), "and clears the failed Remove's message").toHaveCount(0);
  removal = refused(403, 'not_admin', 'Only OcuTalon admins can open settings.');
  await removeButton().click();
  await expect(page.locator('[data-state="denied"]'), 'a 403 on a Remove shows the denied state').toHaveText('Only OcuTalon admins can open settings.');
  await reopen();
  removal = refused(409, 'not_available', OFF);
  await removeButton().click();
  await expect(page.locator('[data-state="off"]'), 'a 409 on a Remove shows the demo line').toHaveText(OFF);

  // (d) a 404 on a Remove (the source is already gone) shows the server's message, and the list loaded again no longer holds it.
  await reopen();
  removal = refused(404, 'not_found', NOT_FOUND);
  await removeButton().click();
  await expect(page.locator('[data-error="sources"]'), "a 404 on a Remove shows the server's message").toHaveText(NOT_FOUND);
  await expect(sources(page).locator('tr[data-source="Existing"]'), 'and the source leaves the list').toHaveCount(0);
  await expect(sources(page).getByText('No sources yet.', { exact: true }), 'which is empty').toBeVisible();
});

test('B14: a changed tool has the changed-tool banner above the table, a new or refused tool has none, and a classification takes it away', async ({ page }) => {
  test.setTimeout(240_000);
  const name = `zzb14${tag()}`;
  try {
    await seedMcpServer(name, [
      { name: 'zz_changed', classification: 'read-only' },
      { name: 'zz_shadow', classification: 'read-only' },
      { name: 'zz_new' },
      { name: 'zz_steady', classification: 'risky' },
      { name: 'zz_second', classification: 'risky' },
    ]);
    // zz_second changes first, so the banners' order is the table's and not the order of the changes
    await clearChangedTool(name, 'zz_second');
    await clearChangedTool(name, 'zz_changed');
    await clearChangedTool(name, 'zz_shadow', true);
    await openMcp(page);
    const banner = tools(page).locator(`[data-banner="tool-changed"][data-tool="zz_changed"][data-server="${name}"]`);
    await expect(banner, 'the changed tool has its banner').toBeVisible();
    await expect(banner, 'in the accepted words').toHaveText(`zz_changed on ${name} changed its description or inputs, so it is Unclassified again. It counts as risky until it is classified below.`);
    await expect(banner.locator('app-icon'), 'with its icon').toHaveCount(1);
    const banners = tools(page).locator(`[data-banner="tool-changed"][data-server="${name}"]`);
    await expect(banners, 'and the other changed tool has its own, so the server has two').toHaveCount(2);
    expect(await banners.evaluateAll((all) => all.map((one) => one.getAttribute('data-tool'))), 'one banner per changed tool, in the order of the tools table (QA)').toEqual(['zz_changed', 'zz_second']);
    const second = tools(page).locator(`[data-banner="tool-changed"][data-tool="zz_second"][data-server="${name}"]`);
    await expect(tools(page).locator(`[data-banner="tool-changed"][data-tool="zz_new"][data-server="${name}"]`), 'a new tool has none').toHaveCount(0);
    await expect(tools(page).locator(`[data-banner="tool-changed"][data-tool="zz_shadow"][data-server="${name}"]`), 'a changed tool that is refused has none').toHaveCount(0);
    const refused = tools(page).locator(`tr[data-tool="zz_shadow"][data-server="${name}"]`);
    await expect(refused.getByRole('cell').nth(1), 'it shows the refusal').toHaveText('Refused: a built-in tool has this name');
    const row = tools(page).locator(`tr[data-tool="zz_changed"][data-server="${name}"]`);
    const group = row.getByRole('radiogroup', { name: `Classification of zz_changed on ${name}`, exact: true });
    await expect(group.getByRole('radio', { name: 'Unclassified (counts as risky)', exact: true }), 'the changed tool is Unclassified').toBeChecked();

    await page.route(`**${MCP}/classify`, async (route) => {
      await route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } }) });
    });
    await group.getByRole('radio', { name: 'Risky', exact: true }).click();
    await expect(row.getByText('Something went wrong inside OcuTalon. Try again.', { exact: true }), 'a save that fails shows the message').toBeVisible();
    await expect(group.getByRole('radio', { name: 'Unclassified (counts as risky)', exact: true }), 'puts the old value back').toBeChecked();
    await expect(banner, 'and the banner stays').toBeVisible();
    await page.unroute(`**${MCP}/classify`);

    await group.getByRole('radio', { name: 'Risky', exact: true }).check();
    await expect(row.locator('p.saved[data-saved="classify"]'), 'Saved shows').toHaveText('Saved');
    await expect(banner, 'the banner goes').toHaveCount(0);
    await expect(second, 'and only that tool\'s banner goes: the other changed tool keeps its own (QA)').toBeVisible();
    await expect(banners, 'one banner is left (QA)').toHaveCount(1);

    await page.reload();
    await expect(page.getByRole('heading', { level: 2, name: 'Tools and MCP servers' })).toBeVisible();
    await expect(tools(page).locator(`tr[data-tool="zz_changed"][data-server="${name}"]`), 'the tool is listed again').toBeVisible();
    await expect(tools(page).locator(`[data-banner="tool-changed"][data-tool="zz_changed"][data-server="${name}"]`), 'and the classified tool has no banner after a reload').toHaveCount(0);
    await expect(tools(page).locator(`[data-banner="tool-changed"][data-tool="zz_second"][data-server="${name}"]`), 'while the changed tool nobody classified still has one (QA)').toBeVisible();
  } finally {
    await dropMcpServer(name);
  }
});
