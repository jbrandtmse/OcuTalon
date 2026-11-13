import { expect, test, type Locator, type Page } from '../support/fixtures';

import { envelope } from '../sign-in/helpers';
import { signInReadmeLoaded } from '../support/floor';
import { approvalState, dropMcpServer, leftovers, seedMcpServer } from '../support/mcp';

/**
 * Story 21.4, Settings > Tools and MCP servers in a real browser, signed in as the README admin (B1 to B5; the sign-in-2 unit). The servers of B1, B3 and B4 are
 * fixture rows made with irisScript (a server row, its tool rows and, for B4, a pending `tool_call` approval row whose ToolSource is the server's toolref), and
 * B2 adds a server through the form (at a loopback address nothing listens on; it has no tools). Every case removes its `zz` servers, tools, approval rows, entries
 * and wallet keys in `finally`.
 *   B1  the section lists a fixture server with its status, tool and unclassified counts, and its tools; "Unclassified only" filters the tools;
 *   B2  the add form shows the field errors under their fields (the first takes focus), and a good add shows the server's message, empties the fields (the secret
 *       field is a password field and no text of the page holds the secret) and lists the server;
 *   B3  a pick in a tool's radiogroup shows the check icon and "Saved" at once, and survives a reload;
 *   B4  the Remove dialog says "Remove {server}? Its 12 tools go at once, and 1 pending approval request for them is canceled."; Cancel keeps the server; Remove
 *       takes it and its tools off the lists and leaves the pending fixture row canceled;
 *   B5  a 409 not_available (fulfilled by the test) shows the online demo's line in place of the content.
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
    await seedMcpServer(name, [{ name: 'zz_open' }, { name: 'zz_read', classification: 'read-only' }, { name: 'zz_risky', classification: 'risky' }]);
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
    const sentence = `Remove ${name}? Its 12 tools go at once, and 1 pending approval request for them is canceled.`;

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
