import { expect, test } from '../support/fixtures';

import { STATE, changeSnapshot, post } from '../support/api';
import { chatItem, fileTransfer, taken } from '../support/files';
import { signIn, envelope } from './helpers';
import { applied, loadedAfter, mainOf, composerOf, railOf } from '../support/floor';
import { cleanFixtureRows, fixtureUser, publishIncident } from '../support/iris';
import { incidentOf, raise, refOf } from '../support/approvals';

/**
 * Story 25.4, the viewer's read-only page in a real browser, signed in as ZzViewer (OCUTALON_VIEWER_USER; the role OcuTalonViewer only), with the real sign-in.
 *   V1  the page loads (no no-role message), /state says viewer true and admin false, the composer is gone and the viewer line shows in its place, History and Usage open,
 *       and there is no Settings link;
 *   V2  with a pending approval card on the viewer's own session (the cards are made as IncidentManager makes them), Approve, Reject, Dismiss and Break the feed are all
 *       absent, though the card, the Dismiss component and the Break the feed box show (so that their absence is not an empty page's), and, with Telegram stubbed as
 *       included, no Telegram, persona, heartbeat or memory card is in the rail, though the rail shows its other sections;
 *   V3  a POST /v1/messages from the page's own context is 403 read_only, and nothing is added to the chat;
 *   V4  an older file reply that is addable shows no Add to documents (and the Saved to memory chip stays), and the add it would send is 403 read_only;
 *   V5  the Documents page takes no drag and no drop of a file: nothing is cancelled, no outline shows and nothing is posted.
 */
const VIEWER_LINE = 'You have the viewer role, so you can look but not change anything.';
const MESSAGES = '/ocutalon/api/v1/messages';
const DOCUMENTS = '/ocutalon/api/v1/documents';

test.describe.configure({ timeout: 120_000 });

test('V1: a viewer signs in to a read-only page: no composer, the viewer line, History and Usage, no Settings link', async ({ page }) => {
  const { user, password } = fixtureUser('VIEWER');
  let state: Record<string, unknown> = {};
  page.on('response', async (response) => {
    if (response.request().method() === 'GET' && new URL(response.url()).pathname === STATE) state = (await response.json().catch(() => state)) as Record<string, unknown>;
  });
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(page.getByText("This IRIS account doesn't have the OcuTalon user role"), 'no no-role message').toHaveCount(0);
  await expect.poll(() => state['viewer'], 'the snapshot says viewer').toBe(true);
  expect(state['admin'], 'and not admin').toBe(false);
  await expect(composerOf(page), 'there is no composer').toHaveCount(0);
  await expect(page.getByText(VIEWER_LINE, { exact: true }), 'the viewer line shows in its place').toBeVisible();
  const nav = page.getByRole('navigation', { name: 'Pages', exact: true });
  await expect(nav.getByRole('link', { name: 'Settings', exact: true }), 'no Settings link').toHaveCount(0);
  for (const name of ['History', 'Usage']) {
    await nav.getByRole('link', { name, exact: true }).click();
    await expect(page.getByRole('heading', { level: 1, name }), `${name} opens`).toBeVisible();
  }
  await nav.getByRole('link', { name: 'Chat', exact: true }).click();
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
});

test('V2: with a pending approval card, no Approve, Reject, Dismiss or Break the feed, and none of the personal rail cards', async ({ page }) => {
  const { user, password } = fixtureUser('VIEWER');
  const rows: string[] = [];
  const requests: string[] = [];
  await changeSnapshot(page, (snapshot) => {
    snapshot['demoMode'] = true;
    const telegram = snapshot['telegram'] as Record<string, unknown> | undefined;
    if (telegram !== undefined) telegram['included'] = true;
  });
  await loadedAfter(page, () => signIn(page, user, password));
  const incident = refOf('inc');
  try {
    await raise(page, user, rows, incident, requests);
    await expect(page.locator('app-chat-panel [data-part="approval"]').first(), 'control: the request card shows').toBeVisible();
    const resolved = refOf('res');
    await applied(page, await publishIncident(user, incidentOf(resolved, [], { state: 'resolved' })));
    await expect(page.locator('app-chat-panel app-incident-dismiss'), 'control: the resolved incident card mounts the Dismiss component, which the viewer gets with no button').toHaveCount(1);
    await expect(page.getByRole('button', { name: /^Approve/ }), 'no Approve').toHaveCount(0);
    await expect(page.getByRole('button', { name: /^Reject/ }), 'no Reject').toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Dismiss', exact: true }), 'no Dismiss').toHaveCount(0);
    await expect(page.locator('app-demo-guide app-break-feed-box'), 'control: the demo guide mounts the Break the feed box, which the viewer gets empty').toHaveCount(1);
    await expect(page.getByRole('button', { name: 'Break the feed', exact: true }), 'no Break the feed').toHaveCount(0);
    await expect(composerOf(page), 'and no composer').toHaveCount(0);
    await expect(railOf(page).getByRole('heading', { name: /^Recent decisions/ }), 'control: the rail shows its other sections').toBeVisible();
    for (const heading of ['Telegram', 'Persona', 'Heartbeat checklist', 'Memory']) {
      await expect(railOf(page).getByRole('heading', { name: heading, exact: true }), `no ${heading} card in the rail`).toHaveCount(0);
    }
  } finally {
    await cleanFixtureRows([...rows, incident]);
  }
});

test('V3: a POST of a message from the page\'s own context is 403 read_only and adds nothing to the chat', async ({ page }) => {
  const { user, password } = fixtureUser('VIEWER');
  await loadedAfter(page, () => signIn(page, user, password));
  const before = (await (await page.request.get(STATE)).json()) as { chat: unknown[] };
  const response = await page.request.post(MESSAGES, { headers: envelope(), data: { clientId: `zz-viewer-${Date.now().toString(36)}`, text: 'zz a viewer cannot send this' } });
  expect(response.status(), await response.text()).toBe(403);
  const body = (await response.json()) as { error: { code: string; message: string } };
  expect(body.error).toEqual({ code: 'read_only', message: VIEWER_LINE });
  const after = (await (await page.request.get(STATE)).json()) as { chat: unknown[] };
  expect(after.chat, 'the chat is as it was').toEqual(before.chat);
});

test('V4: an addable file reply shows a viewer no Add to documents, keeps Saved to memory, and the add is 403 read_only', async ({ page }) => {
  const { user, password } = fixtureUser('VIEWER');
  const fileRef = 'zzViewerAddRef0000000000';
  await changeSnapshot(page, (snapshot) => {
    snapshot['filesReadable'] = true;
    snapshot['onlineDemo'] = false;
    snapshot['chat'] = [
      chatItem({ ref: 'zzViewDocTurn000000000a', fileRead: { fileRef, kind: 'document', read: 1, addable: 1 } }),
      chatItem({ ref: 'zzViewPhoTurn000000000b', fileRead: { fileRef: 'zzViewerPhotoRef000000000', kind: 'photo', read: 1, addable: 0 }, caption: { memoryRef: 'zzmemv1', text: 'A red square on white.' }, replyText: 'A red square on white.' }),
    ];
  });
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  const chat = page.locator('app-chat-panel');
  await expect(chat.locator('app-file-reply'), 'control: both turns mount the controls').toHaveCount(2);
  await expect(page.getByText(VIEWER_LINE, { exact: true }), 'and the page is the viewer\'s').toBeVisible();
  await expect(page.getByRole('button', { name: 'Add to documents', exact: true }), 'no Add to documents').toHaveCount(0);
  await expect(chat.getByText('Saved to memory', { exact: true }), 'the chip stays, once').toHaveCount(1);
  const response = await post(page.request, DOCUMENTS, { fileRef });
  expect(response.status(), await response.text()).toBe(403);
  expect(((await response.json()) as { error: { code: string } }).error.code).toBe('read_only');
});

test('V5: a viewer\'s Documents page takes no drag and no drop of a file, and posts nothing', async ({ page }) => {
  const { user, password } = fixtureUser('VIEWER');
  let posts = 0;
  page.on('request', (request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === DOCUMENTS) posts += 1;
  });
  await loadedAfter(page, () => signIn(page, user, password));
  await page.getByRole('navigation', { name: 'Pages', exact: true }).getByRole('link', { name: 'Documents', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Documents' })).toBeVisible();
  const main = page.locator('main.documents');
  await expect(page.getByRole('button', { name: 'Add documents', exact: true }), 'control: a viewer has no add button').toHaveCount(0);
  const transfer = await fileTransfer(page, 'zz-viewer-drop.pdf');
  expect(await transfer.evaluate((data) => data.types.includes('Files')), 'control: the transfer carries a file').toBe(true);
  expect(await taken(main, 'dragover', transfer), 'no handler takes the drag').toBe(false);
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0))));
  await expect(main, 'no outline shows after the page has rendered the drag').not.toHaveClass(/dragging/);
  expect(await taken(main, 'drop', transfer), 'nor the drop: the browser keeps its own handling').toBe(false);
  await expect(main).not.toHaveClass(/dragging/);
  await page.waitForTimeout(500);
  expect(posts, 'nothing was posted').toBe(0);
});
