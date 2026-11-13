import { expect, test, type Locator, type Page } from '../support/fixtures';

import { envelope } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';
import { approvalState, dropMcpServer, leftovers, seedMcpServer } from '../support/mcp';

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
    await expect(tools(page).getByRole('columnheader'), 'the tools headers').toHaveText(['Tool', 'Server', 'Status', 'Classification']);
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
    expect(await leftovers(name), 'nothing of the server is left').toEqual({ row: 0, tools: 0, entry: 0, key: 0, collection: 0 });
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
