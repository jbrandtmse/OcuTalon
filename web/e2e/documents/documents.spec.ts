import { expect, test, type Locator, type Page, type Response } from '../support/fixtures';

import { README_ACCOUNT, signIn } from '../sign-in/helpers';
import { CARD_MS, loadedAfter, signInReadmeLoaded, unique } from '../support/floor';
import { NAV_LINKS_USER } from '../support/header-nav';
import { publishFixtureEvent } from '../support/devices';
import { chk, cleanFixtureRows, fixtureUser, irisScript, quoted } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 34.2, the Documents page (D1 to D13), in a real browser against a real stack: the README account is signed in (D13: a user without
 * OcuTalonAdmin), the fixture documents are owned by `instance` (a local install shows them to every user) and are removed after each case. DocumentOps is built (Story 19.4), so a
 * valid add reaches a real indexer and a remove really removes: the cases that need a fixed answer (the done answer of D8 and D9, the error answer of D10 and the
 * 404, 500, 501 and 413 answers of D11 and D12) fulfil it in the browser (page.route), and D8 and D10 do so since Story 19.4 (a 10 MB PDF is never indexed for
 * real here, and a remove must not delete the fixture rows by itself). The refusals (D5 to D7) use the real route. The real, unrouted path (an add, the
 * restart, a 10 MB PDF with the web layer in front of the route, and the removes) is the unit live:documents (docker/tests/test-documents.sh).
 */
const DOCUMENTS = '/ocutalon/api/v1/documents';
const TITLE = 'Documents \u00B7 OcuTalon';
const INDEXING = 'Indexing\u2026';
const EMPTY = 'No documents yet. Add a runbook to get cited answers.';
const WRONG_TYPE = "Couldn't read it: it isn't a Markdown, plain-text, PDF or Word (.docx) file.";
const FAILED = "Couldn't read it: something went wrong inside OcuTalon.";
const UNREADABLE = "Couldn't read it: OcuTalon found no text in it.";
const NOT_BUILT = "Couldn't read it: this part of OcuTalon isn't built yet.";
const MB = 1048576;
const REMOVE_FAILED = "Couldn't remove it. Nothing was changed.";

const pagesNav = (page: Page): Locator => page.getByRole('navigation', { name: 'Pages', exact: true });
const documentsLink = (page: Page): Locator => pagesNav(page).getByRole('link', { name: 'Documents', exact: true });
const rowsOf = (page: Page, name: string): Locator => page.locator('li.row').filter({ hasText: name });
const listRegion = (page: Page): Locator => page.getByRole('region', { name: 'Documents', exact: true });
const fileInput = (page: Page): Locator => page.locator('input[type="file"]');

/** The refs of the fixture rows a case made, removed after it. */
const made: string[] = [];

test.afterEach(async () => {
  await cleanFixtureRows(made.splice(0));
});

/** A fixture document owned by the install, with its properties given as strings; returns its Ref. */
async function seed(name: string, fields: Record<string, string> = {}): Promise<string> {
  const lines = await irisScript(
    [
      `Set ref=##class(OcuTalon.Test.Data.Fixture).Document("instance",${quoted(name)},##class(%DynamicObject).%FromJSON(${quoted(JSON.stringify(fields))}))`,
      'Write !,"CHK|ref|",ref',
    ].join('\n'),
  );
  const ref = chk(lines, 'ref');
  if (!ref) throw new Error(`the fixture document could not be made (${lines.join(' ')})`);
  made.push(ref);
  return ref;
}

/** Publishes the `document` event of a document on the README account's session stream. */
function publish(ref: string, name: string, fields: Record<string, string>): Promise<number> {
  return publishFixtureEvent(README_ACCOUNT.user, 'document', 'OcuTalon.Live.Payload.Document', { Ref: ref, Name: name, ...fields });
}

/** Signs the README account in and opens the Documents page from the header. */
async function openDocuments(page: Page): Promise<void> {
  await signInReadmeLoaded(page);
  const listed = page.waitForResponse((response) => response.request().method() === 'GET' && new URL(response.url()).pathname === DOCUMENTS);
  listed.catch(() => undefined);
  await documentsLink(page).click();
  expect((await listed).status(), 'GET /v1/documents').toBe(200);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Documents');
}

/** The answer of the next POST of a document. */
const posted = (page: Page): Promise<Response> => page.waitForResponse((response) => response.request().method() === 'POST' && new URL(response.url()).pathname === DOCUMENTS);

/** D1: the header link, the address, the title, the h1 and the current mark, and no skip links. */
test('D1: Documents is in the header for every signed-in user and opens the page', async ({ page }) => {
  await signInReadmeLoaded(page);
  await expect(documentsLink(page), 'the link is in the header navigation').toBeVisible();
  await expect(documentsLink(page)).not.toHaveAttribute('aria-current', 'page');
  await documentsLink(page).click();
  expect(new URL(page.url()).hash, 'at the address #/documents').toBe('#/documents');
  await expect(page).toHaveTitle(TITLE);
  await expect(page.getByRole('heading', { level: 1 }), 'one h1').toHaveText('Documents');
  await expect(documentsLink(page), 'Documents is the current page').toHaveAttribute('aria-current', 'page');
  await expect(pagesNav(page).getByRole('link', { name: 'Chat', exact: true })).not.toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('link', { name: 'Skip to chat', exact: true }), 'the skip links belong to the main page').toHaveCount(0);
});

/** D2: with no documents the page says so. */
test('D2: with no documents the page reads "No documents yet. Add a runbook to get cited answers."', async ({ page }) => {
  await openDocuments(page);
  await expect(page.getByText(EMPTY)).toBeVisible();
  await expect(page.locator('li.row')).toHaveCount(0);
});

/** D3: the listed rows read Indexing, Ready and Couldn't read it, each with its name, date and size. */
test('D3: listed documents show their name, date, size and status', async ({ page }) => {
  const indexing = unique('indexing');
  const ready = unique('ready');
  const failed = unique('failed');
  await seed(`${indexing}.md`, { Size: '512' });
  await seed(`${ready}.pdf`, { State: 'ready', ContentType: 'pdf', Size: String(3 * MB) });
  await seed(`${failed}.txt`, { State: 'failed', Reason: 'unreadable', ContentType: 'text', Size: '2048' });
  await recordAnnouncements(page);
  await openDocuments(page);
  const one = rowsOf(page, indexing);
  await expect(one).toHaveCount(1);
  await expect(one.locator('.status')).toHaveText(INDEXING);
  await expect(one.locator('.size')).toHaveText('1 KB');
  await expect(one.locator('.when'), 'the date added reads as a time').toHaveText(/\d{1,2}:\d{2}/);
  await expect(one.getByRole('button', { name: `Remove ${indexing}.md`, exact: true })).toBeVisible();
  const two = rowsOf(page, ready);
  await expect(two.locator('.status')).toHaveText('Ready');
  await expect(two.locator('.size')).toHaveText('3 MB');
  const three = rowsOf(page, failed);
  await expect(three.locator('.status')).toHaveText(UNREADABLE);
  await expect(three.locator('.size')).toHaveText('2 KB');
  await expect(page.getByText(EMPTY), 'the empty text is gone').toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Add documents', exact: true }), 'the picker is there beside the rows').toBeVisible();
  await page.waitForTimeout(2500);
  expect(await announcements(page, UNREADABLE), 'a failed row that is not of the user\'s own add is never announced').toBe(0);
});

/** D4: a published `document` event changes a row, and a removed one takes it away, with no reload. */
test('D4: document events turn a row Ready and then remove it, without a reload', async ({ page }) => {
  const name = `${unique('live')}.md`;
  const ref = await seed(name);
  await openDocuments(page);
  const row = rowsOf(page, name);
  await expect(row.locator('.status')).toHaveText(INDEXING);
  await page.evaluate(() => {
    (window as unknown as { documentsMarker: number }).documentsMarker = 7;
  });
  const addedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  await publish(ref, name, { AddedAt: addedAt, Size: '512', State: 'ready' });
  await expect(row.locator('.status'), 'the row reads Ready').toHaveText('Ready', { timeout: CARD_MS });
  await publish(ref, name, { Removed: '1' });
  await expect(row, 'the row leaves').toHaveCount(0, { timeout: CARD_MS });
  expect(await page.evaluate(() => (window as unknown as { documentsMarker?: number }).documentsMarker), 'the page was not reloaded').toBe(7);
});

/** D5: the keyboard reaches Add documents, Enter opens exactly one file chooser, and a .png comes back refused by the real route. */
test('D5: Add documents works by keyboard, and a .png is refused with its reason', async ({ page }) => {
  let choosers = 0;
  // DW-825: Playwright turns file-chooser interception on, asynchronously, when the first 'filechooser' listener is added. It is armed here,
  // before the page opens, so it has been on for the whole sign-in and navigation before the Enter below; a chooser that Enter opens is caught and counted.
  page.on('filechooser', () => {
    choosers += 1;
  });
  await recordAnnouncements(page);
  await openDocuments(page);
  await page.locator('main.documents').focus();
  await page.keyboard.press('Tab');
  const add = page.getByRole('button', { name: 'Add documents', exact: true });
  await expect(add, 'Tab reaches Add documents').toBeFocused();
  expect(choosers, 'no chooser before Enter').toBe(0);
  const chooser = page.waitForEvent('filechooser');
  const answer = posted(page);
  await page.keyboard.press('Enter');
  await (await chooser).setFiles({ name: 'photo.png', mimeType: 'image/png', buffer: Buffer.from('not a document') });
  const response = await answer;
  expect(response.status(), 'the real route refuses a .png').toBe(400);
  const body = (await response.json()) as { error: { code: string }; reason: string };
  expect(`${body.error.code} ${body.reason}`).toBe('bad_document wrong_type');
  const row = rowsOf(page, 'photo.png');
  await expect(row.locator('.status')).toHaveText(WRONG_TYPE);
  await expect(row.getByRole('button', { name: /^Remove/ }), 'a refused file has no Remove').toHaveCount(0);
  await expect.poll(() => announcements(page, WRONG_TYPE), 'the refusal is announced').toBe(1);
  await page.waitForTimeout(2500);
  expect(await announcements(page, WRONG_TYPE), 'and announced once').toBe(1);
  expect(choosers, 'Enter opened exactly one chooser').toBe(1);
});

/** D6: files dropped on the page each go through the same route; the outline shows while they are over the page. */
test('D6: a dropped .exe and .png are each refused with their reason', async ({ page }) => {
  await openDocuments(page);
  const main = page.locator('main.documents');
  const transfer = await page.evaluateHandle(() => {
    const data = new DataTransfer();
    data.items.add(new File(['MZ'], 'setup.exe', { type: 'application/octet-stream' }));
    data.items.add(new File(['not a document'], 'diagram.png', { type: 'image/png' }));
    return data;
  });
  await main.dispatchEvent('dragover', { dataTransfer: transfer });
  await expect(main, 'the page shows the outline while a file is over it').toHaveClass(/dragging/);
  const answer = posted(page);
  await main.dispatchEvent('drop', { dataTransfer: transfer });
  expect((await answer).status()).toBe(400);
  await expect(main, 'and not after the drop').not.toHaveClass(/dragging/);
  await expect(rowsOf(page, 'setup.exe').locator('.status')).toHaveText(WRONG_TYPE);
  await expect(rowsOf(page, 'diagram.png').locator('.status'), 'the second file went through the route as well').toHaveText(WRONG_TYPE);
});

/** D7: a PDF of 11 MB is too large; the page says so with its size. */
test('D7: an 11 MB .pdf is refused as too large', async ({ page }) => {
  await openDocuments(page);
  const answer = posted(page);
  await fileInput(page).setInputFiles({ name: 'big.pdf', mimeType: 'application/pdf', buffer: Buffer.alloc(11 * MB, 65) });
  const response = await answer;
  const body = (await response.json()) as { error: { code: string } };
  expect(['bad_document', 'body_too_large'], `the route itself refuses it before any command (${response.status()}), not the web layer`).toContain(body.error.code);
  await expect(rowsOf(page, 'big.pdf').locator('.status')).toHaveText("Couldn't read it: that file is 11 MB; the limit is 10 MB.", { timeout: 30_000 });
});

/** D8 (Task 0 (c)): the page posts a PDF of exactly 10,485,760 bytes (it does not refuse it as too large) and takes the done answer, which is fulfilled in the
 * browser; the real route's size check for that PDF is the unit live:documents. */
test('D8: a 10 MB .pdf is posted by the page', async ({ page }) => {
  await openDocuments(page);
  await page.route(`**${DOCUMENTS}`, (route) =>
    route.request().method() === 'POST' ? route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', ref: `zzLimit${Date.now().toString(36)}` }) }) : route.fallback(),
  );
  const answer = posted(page);
  await fileInput(page).setInputFiles({ name: 'limit.pdf', mimeType: 'application/pdf', buffer: Buffer.alloc(10 * MB, 65) });
  const response = await answer;
  const status = response.status();
  const text = await response.text();
  expect([200, 500, 501], `the page posts the 14 MB body and gets the fulfilled answer (${status}: ${text.slice(0, 120)})`).toContain(status);
  expect(text, 'and the route does not refuse the file as a bad document').not.toContain('bad_document');
  expect(text, 'or as a body that is too large').not.toContain('body_too_large');
});

/**
 * D9: a .md whose add is answered done shows Indexing, and then the document's row and its Ready event take over; a later failed event of
 * the user's own add is announced once.
 */
test('D9: an accepted .md reads Indexing and then Ready', async ({ page }) => {
  const name = `${unique('added')}.md`;
  const ref = `zzAdded${Date.now().toString(36)}`;
  await recordAnnouncements(page);
  await openDocuments(page);
  await page.route(`**${DOCUMENTS}`, async (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    const body = route.request().postDataJSON() as { name: string; content: string };
    expect(body.name, 'the page sends the file name').toBe(name);
    expect(Buffer.from(body.content, 'base64').toString('utf8'), 'and its bytes in base64').toBe('# Results runbook');
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', ref }) });
  });
  await fileInput(page).setInputFiles({ name, mimeType: 'text/markdown', buffer: Buffer.from('# Results runbook') });
  const row = rowsOf(page, name);
  await expect(row.locator('.status'), 'the page\'s own row reads Indexing').toHaveText(INDEXING);
  await expect(row.getByRole('button', { name: /^Remove/ }), 'and has no Remove yet').toHaveCount(0);
  await seed(name, { Ref: ref });
  const addedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  await publish(ref, name, { AddedAt: addedAt, Size: '17', State: 'ready' });
  await expect(row.locator('.status'), 'the document\'s row reads Ready').toHaveText('Ready', { timeout: CARD_MS });
  await expect(row, 'there is one row for it').toHaveCount(1);
  await expect(row.getByRole('button', { name: `Remove ${name}`, exact: true })).toBeVisible();
  await publish(ref, name, { AddedAt: addedAt, Size: '17', State: 'failed', Reason: 'unreadable' });
  await expect(row.locator('.status'), 'a failed event of the user\'s own add').toHaveText(UNREADABLE, { timeout: CARD_MS });
  await expect.poll(() => announcements(page, UNREADABLE), 'is announced').toBe(1);
  await page.waitForTimeout(2500);
  expect(await announcements(page, UNREADABLE), 'once').toBe(1);
});

/** D10: Remove asks first; Esc and Cancel keep the row; a failed remove says so (announced once, named in the confirm button's description: DW-997); a done one removes the row and focuses the list. */
test('D10: Remove asks first, a failed remove is announced once and named in the confirm button\'s description, and a removed row leaves', async ({ page }) => {
  const name = `${unique('remove')}.md`;
  await seed(name, { State: 'ready' });
  await recordAnnouncements(page);
  await openDocuments(page);
  const row = rowsOf(page, name);
  const remove = row.getByRole('button', { name: `Remove ${name}`, exact: true });
  await expect(remove).toBeVisible();
  const dialog = page.getByRole('dialog', { name: `Remove '${name}'? Answers will stop citing it.`, exact: true });

  await remove.click();
  await expect(dialog, 'the dialog is named by its question').toBeVisible();
  await expect(dialog.getByRole('heading', { level: 2 }), 'first focus is on the heading').toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(remove, 'Esc returns focus to Remove').toBeFocused();
  await expect(row, 'and the row stays').toHaveCount(1);

  await remove.click();
  await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(row, 'Cancel keeps the row').toHaveCount(1);
  await expect(remove).toBeFocused();

  await page.route(`**${DOCUMENTS}/*`, (route) =>
    route.request().method() === 'DELETE' ? route.fulfill({ status: 500, contentType: 'application/json', body: '{"error":{"code":"server_error","message":"zz"}}' }) : route.fallback(),
  );
  await remove.click();
  const confirm = dialog.getByRole('button', { name: 'Remove', exact: true });
  await expect(confirm, 'the confirm button has no description before it fails').not.toHaveAccessibleDescription(REMOVE_FAILED);
  await confirm.click();
  await expect(dialog.getByText(REMOVE_FAILED), 'an error answer to the remove').toBeVisible({ timeout: 30_000 });
  await expect(confirm, 'the confirm button is described by the notice').toHaveAccessibleDescription(REMOVE_FAILED);
  await expect.poll(() => announcements(page, REMOVE_FAILED), { message: 'and the notice is announced once' }).toBe(1);
  await page.waitForTimeout(1000);
  expect(await announcements(page, REMOVE_FAILED), 'and only once').toBe(1);
  await expect(row, 'the row is kept').toHaveCount(1);

  await page.route(`**${DOCUMENTS}/*`, (route) =>
    route.request().method() === 'DELETE' ? route.fulfill({ status: 200, contentType: 'application/json', body: '{"result":"done"}' }) : route.fallback(),
  );
  await dialog.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(row, 'the row leaves').toHaveCount(0);
  await expect(listRegion(page), 'focus goes to the list').toBeFocused();
});

/** D11: an add the route answers 501 or 500 reads as the not-built and failed reasons, and a 413 from anything in front of the route as failed. */
test('D11: a 501 and a 500 answer to an add read as their reasons', async ({ page }) => {
  await openDocuments(page);
  await page.route(`**${DOCUMENTS}`, async (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    const named = (route.request().postDataJSON() as { name: string }).name;
    if (named.startsWith('proxied')) return route.fulfill({ status: 413, contentType: 'text/html', body: '<html><body>413 Request Entity Too Large</body></html>' });
    const unbuilt = named.startsWith('unbuilt');
    return route.fulfill({
      status: unbuilt ? 501 : 500,
      contentType: 'application/json',
      body: JSON.stringify({ error: { code: unbuilt ? 'not_built' : 'server_error', message: 'zz' } }),
    });
  });
  await fileInput(page).setInputFiles({ name: 'unbuilt.md', mimeType: 'text/markdown', buffer: Buffer.from('# one') });
  await expect(rowsOf(page, 'unbuilt.md').locator('.status')).toHaveText(NOT_BUILT);
  await fileInput(page).setInputFiles({ name: 'broken.md', mimeType: 'text/markdown', buffer: Buffer.from('# two') });
  await expect(rowsOf(page, 'broken.md').locator('.status')).toHaveText(FAILED);
  await fileInput(page).setInputFiles({ name: 'proxied.md', mimeType: 'text/markdown', buffer: Buffer.from('# three') });
  await expect(rowsOf(page, 'proxied.md').locator('.status'), 'a 413 that is not the route\'s body_too_large is not read as a size').toHaveText(FAILED);
});

/** D12: a remove the route answers 404 (the document is already gone) closes the dialog and takes the row away. */
test('D12: a 404 answer to a remove closes the dialog and the row leaves', async ({ page }) => {
  const name = `${unique('gone')}.md`;
  await seed(name, { State: 'ready' });
  await openDocuments(page);
  await page.route(`**${DOCUMENTS}/*`, (route) =>
    route.request().method() === 'DELETE'
      ? route.fulfill({ status: 404, contentType: 'application/json', body: '{"error":{"code":"not_found","message":"zz"}}' })
      : route.fallback(),
  );
  const row = rowsOf(page, name);
  await row.getByRole('button', { name: `Remove ${name}`, exact: true }).click();
  const dialog = page.getByRole('dialog', { name: `Remove '${name}'? Answers will stop citing it.`, exact: true });
  await dialog.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(row, 'the row leaves').toHaveCount(0);
  await expect(listRegion(page), 'focus goes to the list').toBeFocused();
});

/** D13: a signed-in user without OcuTalonAdmin has the Documents link too, and it opens the page. */
test('D13: a user who is not an admin has Documents in the header and opens the page', async ({ page }) => {
  const { user, password } = fixtureUser('LIVE');
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(pagesNav(page).getByRole('link'), 'the header navigation holds the links of a user who is not an admin, and no Settings').toHaveText(NAV_LINKS_USER);
  await documentsLink(page).click();
  expect(new URL(page.url()).hash, 'at the address #/documents').toBe('#/documents');
  await expect(page.getByRole('heading', { level: 1 }), 'the page opens').toHaveText('Documents');
  await expect(page.getByRole('button', { name: 'Add documents', exact: true })).toBeVisible();
});
