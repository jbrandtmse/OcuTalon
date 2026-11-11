import { expect, test, type Locator, type Page } from '../support/fixtures';

import { changeSnapshot, EVENTS, MESSAGES } from '../support/api';
import { cleanFixtureRows, fixtureUser, publishCheck, seedCheck } from '../support/iris';
import { composerOf, loadedAfter, railOf } from '../support/floor';
import { signIn } from '../sign-in/helpers';
import { blockLiveSocket } from '../support/socket';

/**
 * K29 (Story 23.7, AC10), in the sign-in-3 project (the sign-in unit's stack, which holds no model key, so no chat turn runs a tool): the demo guide's More to
 * try item "Watch queue backlogs" sends "Watch the queue backlogs." once, as the user's own message, and the Queue-backlog check that the turn's start_watch
 * adds shows in the rail's Background checks with its schedule "A check every minute". While that turn is in flight (its POST is held until the second press is
 * checked) the control is aria-disabled and a second press sends nothing.
 * The sign-in unit has no model, so the POST is answered 202 here (as K9c of more-to-try.spec.ts does) and the check that the turn would start is a row like the
 * one start_watch kind queues makes (its Kind, DisplayName, empty namespace and production, and the user's session), seeded and published as the CheckChanged
 * event does; the turn from the prompt to the row is pinned by Test.Watch.Turns
 * (TestQueuesThroughTheAgent, on the CI mock scenario A/watch-start-queues.json).
 * The texts are written out here as the independent oracle of the page's own.
 * It signs in the sign-in unit's fixture user, as guide/more-to-try.spec.ts does (openAs), with the guide routed to the finish that lists this item.
 */
const LABEL = 'Watch queue backlogs';
const BUTTON = 'Ask to watch queues';
const PROMPT = 'Watch the queue backlogs.';
const CHECK = 'Queue-backlog check';
const SCHEDULE = 'A check every minute';

const guideRegion = (page: Page): Locator => page.getByRole('region', { name: 'Demo guide' });
const linkOf = (page: Page): Locator => guideRegion(page).getByRole('button', { name: 'More to try', exact: true });
const panelOf = (page: Page): Locator => guideRegion(page).getByRole('group', { name: 'Other things to try', exact: true });
const controlOf = (page: Page): Locator =>
  panelOf(page)
    .getByRole('listitem')
    .filter({ has: page.getByText(LABEL, { exact: true }) })
    .getByRole('button', { name: BUTTON, exact: true });

/**
 * Signs the sign-in unit's fixture user in with a routed demo guide at its finish that lists the item, so that the guide and its More to try panel show for it
 * whatever its own guide state is, and waits for the loaded page. The page has no status (no allowance, no banner) whatever the stack's state is: the snapshot's
 * statuses are emptied, and the live socket is blocked and the polls drop guide.state and status events, so the routed guide stands; every other event (the
 * chat's and the rail's) reaches the page. A poll answer that is not JSON passes as it is.
 */
async function openAs(page: Page, user: string, password: string): Promise<void> {
  await blockLiveSocket(page);
  await page.route(new RegExp(`${EVENTS}\\?`), async (route) => {
    const response = await route.fetch();
    try {
      const body = (await response.json()) as { events: Array<{ type: string }> };
      body.events = body.events.filter((event) => event.type !== 'guide.state' && event.type !== 'status');
      await route.fulfill({ response, json: body });
    } catch {
      await route.fulfill({ response });
    }
  });
  await changeSnapshot(page, (snapshot) => {
    snapshot['status'] = [];
    snapshot['guide'] = {
      runEpoch: 1,
      step: 5,
      finished: true,
      steps: [1, 2, 3, 4, 5].map((step) => ({ step, done: true })),
      breakFeed: { active: false, reason: 'not_watching' },
      step4Variant: 'unpaired',
      telegramRow: false,
      features: ['queueWatch'],
    };
  });
  await loadedAfter(page, () => signIn(page, user, password));
  await expect(composerOf(page)).toBeVisible();
}

test('K29: Ask to watch queues sends its prompt once and the rail gains the Queue-backlog check', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  const { user, password } = fixtureUser('NOTICE');
  const posts: Array<{ text: string; fromGuide: boolean }> = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && request.url().endsWith(MESSAGES)) {
      posts.push(request.postDataJSON() as { text: string; fromGuide: boolean });
    }
  });
  let release: () => void = () => undefined;
  const held = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route(`**${MESSAGES}`, async (route) => {
    if (route.request().method() !== 'POST') return route.fallback();
    await held;
    const body = route.request().postDataJSON() as { clientId: string };
    return route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify({ clientId: body.clientId }) });
  });
  const made: string[] = [];
  try {
    await openAs(page, user, password);
    const link = linkOf(page);
    if ((await link.getAttribute('aria-expanded')) !== 'true') await link.click();
    await expect(panelOf(page)).toBeVisible();
    const control = controlOf(page);
    await expect(control, 'the item is in the panel with its control').toBeVisible();
    await control.click();
    await expect.poll(() => posts.length, { message: 'the prompt was posted' }).toBe(1);
    expect(posts[0]!.text).toBe(PROMPT);
    expect(posts[0]!.fromGuide, 'as the user\'s own message').toBe(false);
    await expect(control, 'while its turn is in flight the control is aria-disabled').toHaveAttribute('aria-disabled', 'true');
    await control.click({ force: true });
    await page.waitForTimeout(500);
    expect(posts, 'a press while the turn was in flight sent nothing').toHaveLength(1);
    release();
    // What the turn's start_watch kind queues makes: the session's queue row, and the check event that puts it in the rail.
    const check = { kind: 'queues', namespace: '', production: '', displayName: CHECK };
    const ref = await seedCheck(user, check);
    made.push(ref);
    await publishCheck(user, { ...check, ref });
    const row = railOf(page).locator('li.row').filter({ hasText: CHECK });
    await expect(row, 'the rail lists the Queue-backlog check').toHaveCount(1, { timeout: 60_000 });
    await expect(row, 'with its schedule').toContainText(SCHEDULE);
    expect(posts, 'and nothing more was sent').toHaveLength(1);
  } finally {
    release();
    await cleanFixtureRows(made);
  }
});
