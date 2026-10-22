import { expect, test, type Response } from '@playwright/test';

import { README_ACCOUNT, signInReadme, watchViolations } from '../sign-in/helpers';
import { notBuilt } from './not-built';

/** The page's state snapshot (UJ-1 step 1). */
const STATE = '/ocutalon/api/v1/state';

/**
 * The floor of the demo path: a fresh install, the README account signs in, and the page loads its snapshot once, with
 * the header in place and no Content-Security-Policy violation or page error.
 */
test('signs in with the README account and loads the page snapshot', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);
  const answered: Response[] = [];
  page.on('response', (response) => {
    if (new URL(response.url()).pathname === STATE) answered.push(response);
  });

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.locator('app-header .wordmark')).toHaveText('OcuTalon');
  await expect(page.getByRole('button', { name: README_ACCOUNT.user })).toBeVisible();
  expect(answered.map((response) => response.status()), 'the page asked for /state once and got 200').toEqual([200]);
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});

notBuilt('the chat panel and the composer', '2.5');
notBuilt('the simulated phone and the simulated mailbox, each labelled Simulated', '4.7');
notBuilt('the demo guide lists the steps, each with its one-click prompt', '4.7');
notBuilt('Break the feed is marked as a demo control', '4.7');
