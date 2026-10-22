import { expect, test, type Response } from '@playwright/test';

import { README_ACCOUNT, signInReadme, watchViolations } from '../sign-in/helpers';
import { notBuilt } from './not-built';

/** The page's state snapshot (UJ-1 step 1). */
const STATE = '/ocutalon/api/v1/state';
const EVENTS = '/ocutalon/api/v1/events';
const MESSAGES = '/ocutalon/api/v1/messages';

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

/**
 * The floor of the chat part of step 1: a fresh install shows the README account the empty chat panel and the composer. The stack
 * has no fixture user and no model key, so nothing is sent: Shift+Enter adds a line to the field and no POST /messages is seen. The
 * test checks what both demo modes show, so it leaves out the panel's last line (the demo mode has its own).
 */
test('shows the empty chat panel and the composer', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);
  const posted: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST' && new URL(request.url()).pathname === MESSAGES) posted.push(request.url());
  });

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const main = page.getByRole('main');
  const empty = main.locator('app-empty-chat');
  await expect(empty.locator('p.headline')).toHaveText('For everything that arrives, OcuTalon makes one attention decision');
  await expect(empty.locator('app-outcome-chip')).toHaveText(['Ignore', 'Digest', 'Tell now', 'Act']);
  await expect(empty.locator('.meaning')).toHaveText([
    'Recorded; nobody notified',
    'Saved for later; nobody notified now',
    'Needs you now',
    'OcuTalon took or requested an action',
  ]);
  await expect(empty.locator('.line').first()).toHaveText('It watches your productions from inside IRIS, and every decision is a production message you can trace.');
  await expect(empty.locator('.line').nth(1)).toHaveText('Anything risky waits for your approval.');

  const field = main.getByRole('textbox', { name: 'Message OcuTalon' });
  await expect(field).toBeVisible();
  await expect(main.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
  await field.pressSequentially('one');
  await field.press('Shift+Enter');
  await field.pressSequentially('two');
  expect(await field.inputValue(), 'Shift+Enter adds a line').toBe('one\ntwo');
  await expect(main.locator('[aria-live], [role="log"], [role="status"], [role="alert"]'), 'nothing in main is a live region').toHaveCount(0);
  expect(posted, 'no message was sent').toEqual([]);
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});

notBuilt('the simulated phone and the simulated mailbox, each labelled Simulated', '4.7');
notBuilt('the demo guide lists the steps, each with its one-click prompt', '4.7');
notBuilt('Break the feed is marked as a demo control', '4.7');
