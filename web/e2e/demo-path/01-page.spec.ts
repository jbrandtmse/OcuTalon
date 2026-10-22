import { expect, test, type Response } from '@playwright/test';

import { README_ACCOUNT, signInReadme, watchViolations } from '../sign-in/helpers';
import { notBuilt } from './not-built';

/** The page's state snapshot (UJ-1 step 1). */
const STATE = '/ocutalon/api/v1/state';
const EVENTS = '/ocutalon/api/v1/events';

/**
 * The floor of the demo path: a fresh install, the README account signs in, and the page loads its snapshot once, with
 * the header in place and no Content-Security-Policy violation or page error, and within 3 seconds of the load an
 * /events poll that carries the snapshot's two cursors is answered 200.
 */
test('signs in with the README account and loads the page snapshot', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);
  const answered: Response[] = [];
  const polled: Response[] = [];
  page.on('response', (response) => {
    const path = new URL(response.url()).pathname;
    if (path === STATE) answered.push(response);
    if (path === EVENTS) polled.push(response);
  });

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect.poll(() => polled.length, { message: 'within 3 s of the load, an /events poll was answered', timeout: 3000 }).toBeGreaterThan(0);
  const snapshot = (await answered[0].json()) as { streams: { session: number; instance: number } };
  expect(polled[0].status(), 'the poll was answered 200').toBe(200);
  const params = new URL(polled[0].url()).searchParams;
  expect(params.get('after'), "the poll carries the snapshot's session cursor").toBe(String(snapshot.streams.session));
  expect(params.get('afterInstance'), 'and its instance cursor').toBe(String(snapshot.streams.instance));
  await expect(page.locator('app-header .wordmark')).toHaveText('OcuTalon');
  await expect(page.getByRole('button', { name: README_ACCOUNT.user })).toBeVisible();
  expect(answered.map((response) => response.status()), 'the page asked for /state once and got 200').toEqual([200]);
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});

notBuilt('the chat panel and the composer', '2.5');
notBuilt('the simulated phone and the simulated mailbox, each labelled Simulated', '4.7');
notBuilt('the demo guide lists the steps, each with its one-click prompt', '4.7');
notBuilt('Break the feed is marked as a demo control', '4.7');
