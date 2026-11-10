import { expect, test, type Locator, type Page, type Response } from '../support/fixtures';

import { changeSnapshot, STATE } from '../support/api';
import { README_ACCOUNT } from '../sign-in/helpers';
import { publishFixtureEvent } from '../support/devices';
import { CARD_MS, signInReadmeLoaded, unique } from '../support/floor';
import { blockLiveSocket } from '../support/socket';

/**
 * Story 20.3, the sample control of More to try's items 6 and 8, on the sign-in stack with the README account and the real guide. The
 * server's feature list is the real one (the cases assert that it holds `documents` and `sources`); the visitor's list is what GET
 * /v1/documents says in each case (page.route), and the add of G2 and G3 is fulfilled in the browser, so that no document is stored.
 *   - G1: with no documents, items 6 and 8 are native buttons "Add the sample runbook"; with one, they are the links to the Documents
 *     page; a published `document` event flips the buttons to links, and its `removed` event flips them back, with no reload;
 *   - G2: pressing item 6's button lands on #/documents with focus on the page's Add the sample runbook, which that press presses: exactly
 *     one POST, named "Sample runbook.md", sent from the Documents page and not by the panel; G2b: item 8's button does the same;
 *   - G3: Tab and Enter do the same;
 *   - G4: with the sample already listed when the page loads, the same press puts focus on the list region and posts nothing;
 *   - G5: with a guide that does not list `documents`, an empty list never turns item 8 into the sample button (the control is gated on the
 *     `documents` item);
 *   - G6: a snapshot reload asks for the list again, so a document that was added elsewhere turns the buttons into links with no `document` event.
 */
const DOCUMENTS = '**/ocutalon/api/v1/documents';
const SAMPLE_BUTTON = 'Add the sample runbook';
const OPEN_LINK = 'Open the Documents page';
const SAMPLE_NAME = 'Sample runbook.md';
const SIX = 'Ask about a document';
const EIGHT = 'See where an answer came from';

const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const linkOf = (page: Page): Locator => guideRegion(page).getByRole('button', { name: 'More to try', exact: true });
const panelOf = (page: Page): Locator => guideRegion(page).getByRole('group', { name: 'Other things to try', exact: true });
const itemOf = (page: Page, label: string): Locator => panelOf(page).getByRole('listitem').filter({ has: page.getByText(label, { exact: true }) });
const listRegion = (page: Page): Locator => page.getByRole('region', { name: 'Documents', exact: true });
/** The Documents page's own button (the panel's control of the same name is on the main page). */
const sampleButton = (page: Page): Locator => page.locator('app-documents-page').getByRole('button', { name: SAMPLE_BUTTON, exact: true });

/** One document as GET /v1/documents lists it. */
const listing = (ref: string, name: string): Record<string, unknown> => ({ ref, name, addedAt: '2025-03-02T10:00:00Z', size: 10, state: 'ready' });

/** Answers GET /v1/documents with the list that `current` returns now, and passes the other methods on. */
async function routeList(page: Page, current: () => Array<Record<string, unknown>>): Promise<void> {
  await page.route(DOCUMENTS, (route) =>
    route.request().method() === 'GET' ? route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ documents: current() }) }) : route.fallback(),
  );
}

/** Signs the README account in, opens the panel from the link, and checks that the server lists the documents and sources items. */
async function openPanel(page: Page, options: { documents?: boolean } = {}): Promise<void> {
  const listed = documentsAnswered(page);
  await signInReadmeLoaded(page);
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const response = await page.request.get(STATE);
  expect(response.status(), await response.text()).toBe(200);
  const features = ((await response.json()) as { guide: { features?: string[] } }).guide.features ?? [];
  expect(features, 'the instance lists the features the case needs').toEqual(expect.arrayContaining(options.documents === false ? ['sources'] : ['documents', 'sources']));
  if ((await linkOf(page).getAttribute('aria-expanded')) !== 'true') await linkOf(page).click();
  await expect(panelOf(page)).toBeVisible();
  await listed;
  await afterRender(page);
}

/** Resolves when the app's next GET /v1/documents has answered; the panel's service asks for the list when the panel is made. */
function documentsAnswered(page: Page): Promise<void> {
  return new Promise<void>((resolve) => {
    const on = (response: Response): void => {
      if (response.request().method() === 'GET' && response.url().endsWith('/v1/documents')) {
        page.off('response', on);
        resolve();
      }
    };
    page.on('response', on);
  });
}

/** Two animation frames: the page has drawn what an answer it just received changed. */
function afterRender(page: Page): Promise<void> {
  return page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
}

/** The `document` event of the README account's session stream, for a document the list does not hold. */
function publish(ref: string, name: string, fields: Record<string, string>): Promise<number> {
  return publishFixtureEvent(README_ACCOUNT.user, 'document', 'OcuTalon.Live.Payload.Document', { Ref: ref, Name: name, ...fields });
}

/** Counts the POSTs to /v1/documents and holds each one until `release` is called; the answer is a fulfilled 200 with a ref the stack never stored. */
function holdPosts(page: Page): Promise<{ bodies: Array<{ name: string; content: string }>; hashes: string[]; release: () => void }> {
  const bodies: Array<{ name: string; content: string }> = [];
  const hashes: string[] = [];
  let release: () => void = () => undefined;
  const open = new Promise<void>((resolve) => {
    release = resolve;
  });
  return page
    .route(DOCUMENTS, async (route) => {
      if (route.request().method() !== 'POST') return route.fallback();
      bodies.push(route.request().postDataJSON() as { name: string; content: string });
      hashes.push(new URL(page.url()).hash);
      await open;
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ result: 'done', ref: 'zzG2sample' }) });
    })
    .then(() => ({ bodies, hashes, release }));
}

/** G1: the control follows the visitor's own list, live. */
test('G1: with no documents items 6 and 8 are the Add the sample runbook button, with one they are links, and a document event flips them', async ({ page }) => {
  const held: Array<Record<string, unknown>> = [];
  await routeList(page, () => held);
  await openPanel(page);
  for (const label of [SIX, EIGHT]) {
    const item = itemOf(page, label);
    const button = item.getByRole('button', { name: SAMPLE_BUTTON, exact: true });
    await expect(button, `${label}: the sample button`).toHaveCount(1);
    await expect(button).toHaveAttribute('type', 'button');
    await expect(item.getByRole('link'), `${label}: and no link`).toHaveCount(0);
  }

  const name = `${unique('g1')}.md`;
  const ref = `zzG1${Date.now().toString(36)}`;
  await page.evaluate(() => {
    (window as unknown as { sampleMarker: number }).sampleMarker = 5;
  });
  await publish(ref, name, { AddedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), Size: '10', State: 'ready' });
  for (const label of [SIX, EIGHT]) {
    const link = itemOf(page, label).getByRole('link', { name: OPEN_LINK, exact: true });
    await expect(link, `${label}: a document event turns the button into the link`).toHaveAttribute('href', /#\/documents$/, { timeout: CARD_MS });
    await expect(itemOf(page, label).getByRole('button', { name: SAMPLE_BUTTON, exact: true })).toHaveCount(0);
  }
  await publish(ref, name, { Removed: '1' });
  for (const label of [SIX, EIGHT]) {
    await expect(itemOf(page, label).getByRole('button', { name: SAMPLE_BUTTON, exact: true }), `${label}: a removed event empties the list again`).toHaveCount(1, { timeout: CARD_MS });
  }
  expect(await page.evaluate(() => (window as unknown as { sampleMarker?: number }).sampleMarker), 'the page was not reloaded').toBe(5);
});

/** G1b: a list that holds a document keeps the links, and a list that cannot be read does too. */
test('G1b: with a document, or with a list that failed, items 6 and 8 stay links to the Documents page', async ({ page }) => {
  await routeList(page, () => [listing('zzG1b', 'g1b.md')]);
  await openPanel(page);
  for (const label of [SIX, EIGHT]) {
    await expect(itemOf(page, label).getByRole('link', { name: OPEN_LINK, exact: true })).toHaveAttribute('href', /#\/documents$/);
    await expect(itemOf(page, label).getByRole('button', { name: SAMPLE_BUTTON, exact: true })).toHaveCount(0);
  }
  await page.route(DOCUMENTS, (route) => (route.request().method() === 'GET' ? route.fulfill({ status: 500, contentType: 'application/json', body: '{"error":{"code":"server_error","message":"zz"}}' }) : route.fallback()));
  const failed = documentsAnswered(page);
  await page.reload();
  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  if ((await linkOf(page).getAttribute('aria-expanded')) !== 'true') await linkOf(page).click();
  await failed;
  await afterRender(page);
  for (const label of [SIX, EIGHT]) {
    await expect(itemOf(page, label).getByRole('link', { name: OPEN_LINK, exact: true }), `${label}: unknown keeps the link`).toBeVisible();
  }
});

/** A press of the item's sample button lands on the Documents page, on the page's own button, which posts the sample once. */
async function pressLandsOnSample(page: Page, label: string): Promise<void> {
  await routeList(page, () => []);
  const posts = await holdPosts(page);
  await openPanel(page);
  await itemOf(page, label).getByRole('button', { name: SAMPLE_BUTTON, exact: true }).click();
  await expect.poll(() => new URL(page.url()).hash, 'the press opens the Documents page').toBe('#/documents');
  const button = sampleButton(page);
  await expect(button, 'the page\'s button is busy with its press').toHaveAttribute('aria-busy', 'true');
  await expect(button).toBeFocused();
  await expect(button, 'it keeps its label and is aria-disabled, never disabled').toHaveAttribute('aria-disabled', 'true');
  await expect(button).not.toHaveAttribute('disabled', /.*/);
  await expect.poll(() => posts.bodies.map((body) => body.name), 'one POST, named for the sample').toEqual([SAMPLE_NAME]);
  expect(posts.hashes, 'sent from the Documents page, not by the panel').toEqual(['#/documents']);
  posts.release();
  await expect(button, 'the pending row lists the sample, so the button leaves').toHaveCount(0);
  await expect(listRegion(page), 'and focus goes to the list region').toBeFocused();
  await page.waitForTimeout(500);
  expect(posts.bodies.length, 'still one POST').toBe(1);
}

/** G2: item 6's press lands on the Documents page, on the page's own button, which posts the sample once. */
test('G2: the sample button of item 6 opens the Documents page, focuses its Add the sample runbook and makes one POST', async ({ page }) => {
  await pressLandsOnSample(page, SIX);
});

/** G2b: item 8's control is the same sample button, and its press does the same. */
test('G2b: the sample button of item 8 opens the Documents page, focuses its Add the sample runbook and makes one POST', async ({ page }) => {
  await pressLandsOnSample(page, EIGHT);
});

/** G3: Tab reaches the control, a native button, and Enter does the same as a click. */
test('G3: Tab reaches item 6\'s sample button and Enter presses it', async ({ page }) => {
  await routeList(page, () => []);
  const posts = await holdPosts(page);
  await openPanel(page);
  const control = itemOf(page, SIX).getByRole('button', { name: SAMPLE_BUTTON, exact: true });
  await panelOf(page).focus();
  for (let tabs = 0; tabs < 15 && !(await control.evaluate((node) => node === document.activeElement)); tabs += 1) await page.keyboard.press('Tab');
  await expect(control, 'Tab reaches it').toBeFocused();
  expect(await control.evaluate((node) => node.tagName), 'a native button').toBe('BUTTON');
  await page.keyboard.press('Enter');
  await expect.poll(() => new URL(page.url()).hash).toBe('#/documents');
  await expect(sampleButton(page)).toBeFocused();
  await expect.poll(() => posts.bodies.length, 'the Documents page makes the one POST').toBe(1);
  expect(posts.bodies[0]!.name).toBe(SAMPLE_NAME);
  posts.release();
  await expect(listRegion(page)).toBeFocused();
});

/** G4: with the sample already listed, the press only focuses the list. */
test('G4: when the list already holds the sample, the press puts focus on the list region and posts nothing', async ({ page }) => {
  const held: Array<Record<string, unknown>> = [];
  await routeList(page, () => held);
  const posts = await holdPosts(page);
  await openPanel(page);
  const control = itemOf(page, SIX).getByRole('button', { name: SAMPLE_BUTTON, exact: true });
  await expect(control).toBeVisible();
  held.push(listing('zzG4', SAMPLE_NAME));
  await control.click();
  await expect.poll(() => new URL(page.url()).hash).toBe('#/documents');
  await expect(listRegion(page).locator('li.row').filter({ hasText: SAMPLE_NAME })).toHaveCount(1);
  await expect(listRegion(page)).toBeFocused();
  await expect(sampleButton(page), 'no sample button while the sample is listed').toHaveCount(0);
  await page.waitForTimeout(500);
  expect(posts.bodies, 'nothing was posted').toEqual([]);
});

/** G5: the control is gated on the `documents` item, so a guide without it keeps item 8's link whatever the list holds. */
test('G5: with a guide that does not list documents, an empty list leaves item 8 a link and offers no sample button', async ({ page }) => {
  await routeList(page, () => []);
  await changeSnapshot(page, (snapshot) => {
    const guide = snapshot['guide'] as { features?: string[] };
    guide.features = (guide.features ?? []).filter((id) => id !== 'documents');
  });
  await openPanel(page, { documents: false });
  await expect(itemOf(page, SIX), 'item 6 is not listed without the documents feature').toHaveCount(0);
  await expect(itemOf(page, EIGHT).getByRole('link', { name: OPEN_LINK, exact: true }), 'item 8 stays the link').toHaveAttribute('href', /#\/documents$/);
  await expect(panelOf(page).getByRole('button', { name: SAMPLE_BUTTON, exact: true }), 'and no item offers the sample').toHaveCount(0);
});

/** G6: a snapshot reload (a poll with another epoch) asks for the list again; the document that the list now holds turns the buttons into links. */
test('G6: a snapshot reload asks for the list again, so a document added elsewhere turns the buttons into links with no document event', async ({ page }) => {
  const held: Array<Record<string, unknown>> = [];
  await routeList(page, () => held);
  await blockLiveSocket(page);
  let armed = false;
  let changed = false;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    if (!armed || changed) return route.fulfill({ response });
    changed = true;
    const body = (await response.json()) as Record<string, unknown>;
    body['epoch'] = 'ZzE2EOtherEpoch';
    return route.fulfill({ response, json: body });
  });
  await openPanel(page);
  for (const label of [SIX, EIGHT]) await expect(itemOf(page, label).getByRole('button', { name: SAMPLE_BUTTON, exact: true }), `${label}: the sample button first`).toHaveCount(1);
  held.push(listing('zzG6', 'g6.md'));
  armed = true;
  for (const label of [SIX, EIGHT]) {
    await expect(itemOf(page, label).getByRole('link', { name: OPEN_LINK, exact: true }), `${label}: the reloaded list turns the button into the link`).toHaveAttribute('href', /#\/documents$/, { timeout: CARD_MS });
  }
  expect(changed, 'the poll with another epoch was served').toBe(true);
});
