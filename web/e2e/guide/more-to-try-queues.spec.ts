import { expect, test, type Locator, type Page } from '../support/fixtures';

import { MESSAGES } from '../support/api';
import { fixtureUser, irisScript, quoted } from '../support/iris';
import { composerOf, openFloor, railOf } from '../support/floor';

/**
 * K29 (Story 23.7, AC10), on the real stack with the CI mock (ci/mock/scenarios/B/queue-watch-ask.json): the demo guide's More to try item "Watch queue
 * backlogs" sends "Watch the queue backlogs." once, as the user's own message, and the chat turn's start_watch with kind queues adds the Queue-backlog check
 * to the rail's Background checks, with its schedule "A check every minute". While that turn is in flight (its POST is held until the second press is
 * checked) the control is aria-disabled and a second press sends nothing.
 * The texts are written out here as the independent oracle of the page's own.
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

/** Deletes the queue-backlog rows that the user's session made, so that no later case sees the check. */
async function removeQueueChecks(user: string): Promise<void> {
  await irisScript(
    `Set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.BackgroundCheck WHERE Kind = 'queues' AND AskedBy = ?", ${quoted(user)})\nWrite !,"CHK|clean|"_rs.%SQLCODE`,
  );
}

test('K29: Ask to watch queues sends its prompt once and the rail gains the Queue-backlog check', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  const { user } = fixtureUser('FLOOR');
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
    if (route.request().method() === 'POST') await held;
    await route.fallback();
  });
  await removeQueueChecks(user);
  try {
    await openFloor(page);
    await expect(composerOf(page)).toBeVisible();
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
    const row = railOf(page).locator('li.row').filter({ hasText: CHECK });
    await expect(row, 'the rail lists the Queue-backlog check').toHaveCount(1, { timeout: 60_000 });
    await expect(row, 'with its schedule').toContainText(SCHEDULE);
    expect(posts, 'and nothing more was sent').toHaveLength(1);
  } finally {
    release();
    await removeQueueChecks(user);
  }
});
