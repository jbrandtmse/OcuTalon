import { expect, test } from '../support/fixtures';

import { STATE, changeSnapshot } from '../support/api';
import { signIn, envelope } from './helpers';
import { applied, loadedAfter, mainOf, composerOf, railOf } from '../support/floor';
import { cleanFixtureRows, fixtureUser, publishIncident } from '../support/iris';
import { incidentOf, raise, refOf } from '../support/approvals';

/**
 * Story 25.4, the viewer's read-only page in a real browser, signed in as ZzViewer (OCUTALON_VIEWER_USER; the role OcuTalonViewer only), with the real sign-in.
 *   V1  the page loads (no no-role message), /state says viewer true and admin false, the composer is gone and the viewer line shows in its place, History and Usage open,
 *       and there is no Settings link;
 *   V2  with a pending approval card on the viewer's own session (the cards are made as IncidentManager makes them), Approve, Reject, Dismiss and Break the feed are all
 *       absent, though the card itself shows (so that their absence is not an empty page's), and no Telegram, persona, heartbeat or memory card is in the rail;
 *   V3  a POST /v1/messages from the page's own context is 403 read_only, and nothing is added to the chat.
 */
const VIEWER_LINE = 'You have the viewer role, so you can look but not change anything.';
const MESSAGES = '/ocutalon/api/v1/messages';

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
    await expect(page.getByRole('button', { name: 'Break the feed', exact: true }), 'no Break the feed').toHaveCount(0);
    await expect(composerOf(page), 'and no composer').toHaveCount(0);
    for (const heading of ['Telegram', 'Persona', 'Heartbeat', 'Memory']) {
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
