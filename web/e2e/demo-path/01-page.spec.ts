import { expect, test, type Response } from '@playwright/test';

import { README_ACCOUNT, signInReadme, watchViolations } from '../sign-in/helpers';

/** The page's state snapshot (UJ-1 step 1). */
const STATE = '/ocutalon/api/v1/state';
const EVENTS = '/ocutalon/api/v1/events';
const MESSAGES = '/ocutalon/api/v1/messages';

/** The exact prompts of the guide's steps (EXPERIENCE, the demo guide), written out here as the independent oracle of the page's own. */
const P1 = 'Watch the Orders production and only tell me if something needs me.';
const P2 = 'Remind me in 1 minute to stretch.';
const P3 = 'Press Break the feed. The partner will send 50 orders in a new date format.';
const P4 = 'Approve the fix on the simulated phone, or in the chat.';
const P5 = "Open the incident's trace: watch your assistant in Visual Trace like any other feed, with every step it took and the tokens and cost of each decision.";

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
 * stack is in demo mode (every throwaway is), so the panel's last line points at the demo guide above, and the rail's empty checks say that step 1 of the guide sets up a watch (Story 4.4).
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
  await expect(empty.locator('.line').nth(2), 'the stack is in demo mode: the last line points at the demo guide').toHaveText('Start with step 1 of the demo guide above.');

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

/**
 * The floor of the status rail (REL-2, UX-DR51): on a fresh install the README account sees the rail as the region Status with its four
 * sections in order, each with its count and its empty state, both hints, no Telegram section and no live region in the rail.
 */
test('shows the status rail with its sections, counts and empty states', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const rail = page.getByRole('region', { name: 'Status', exact: true });
  await expect(rail, 'the rail is the region Status').toHaveCount(1);
  const headings = rail.getByRole('heading', { level: 3 });
  await expect(headings, 'four sections in order').toHaveCount(4);
  const names = ['Approval requests', 'Background checks', 'Reminders', 'Recent decisions'];
  for (const [i, label] of names.entries()) {
    await expect(headings.nth(i), `heading ${i + 1} is named with its count`).toHaveAccessibleName(`${label}, 0`);
  }
  await expect(rail.locator('h3 > [aria-hidden="true"]'), 'and shows it').toHaveText(names.map((label) => `${label} (0)`));
  await expect(rail.locator('.empty'), 'each list shows its empty text').toHaveText([
    'None waiting.',
    'Nothing yet. Step 1 of the guide sets up a watch.',
    'None pending.',
    'No decisions yet.',
  ]);
  await expect(rail.locator('.hint'), 'the check and reminder hints sit under the lists').toHaveText([
    'To stop, ask: "Stop watching Orders."',
    'To cancel, ask: "Cancel my reminder to stretch."',
  ]);
  await expect(rail.getByRole('heading', { name: 'Telegram' }), 'a release without Telegram has no Telegram section').toHaveCount(0);
  await expect(rail.locator('[aria-live], [role="log"], [role="status"], [role="alert"]'), 'nothing in the rail is a live region').toHaveCount(0);
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});

/**
 * The floor of the simulated devices (UJ-1 step 1, FR-13, Story 4.5): the demo-mode install shows the device panel with its two tabs, and the
 * phone and the mailbox each carry the Simulated label inside them.
 */
test('the simulated phone and the simulated mailbox, each labelled Simulated', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const devices = page.getByRole('region', { name: 'Simulated devices' });
  await expect(devices, 'the device panel is on the page').toHaveCount(1);
  const phoneTab = devices.getByRole('tab', { name: /^Simulated phone/ });
  const mailboxTab = devices.getByRole('tab', { name: /^Simulated mailbox/ });
  await expect(phoneTab).toHaveCount(1);
  await expect(mailboxTab).toHaveCount(1);

  await phoneTab.click();
  await expect(phoneTab).toHaveAttribute('aria-selected', 'true');
  await expect(devices.locator('app-simulated-phone app-simulated-label'), 'the phone is labelled Simulated').toHaveText('Simulated');
  await expect(devices.locator('app-simulated-phone app-simulated-label')).toBeVisible();

  await mailboxTab.click();
  await expect(mailboxTab).toHaveAttribute('aria-selected', 'true');
  await expect(devices.locator('.mailbox-header app-simulated-label'), 'the mailbox is labelled Simulated').toHaveText('Simulated');
  await expect(devices.locator('.mailbox-header app-simulated-label')).toBeVisible();
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});

/**
 * The floor of the demo guide (UJ-1, Story 4.4 and 4.7): the region "Demo guide" lists the five steps by name, and selecting each shows its
 * exact prompt and its action. Nothing is sent: Send and the other buttons are not pressed. A fresh install has no incident, so step 5 shows
 * its prompt with no Open the trace.
 */
test('the demo guide lists the steps, each with its one-click prompt', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);
  const posted: string[] = [];
  page.on('request', (request) => {
    if (request.method() === 'POST') posted.push(new URL(request.url()).pathname);
  });

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  posted.length = 0;
  const guide = page.getByRole('region', { name: 'Demo guide' });
  await expect(guide).toHaveCount(1);
  const steps = guide.locator('ol .step');
  await expect(steps, 'five steps').toHaveCount(5);
  await expect(guide.locator('ol .step .step-label')).toHaveText(['Watch', 'Reminder', 'Break the feed', 'Approve', 'Open the trace']);
  const prompt = guide.locator('.prompt');
  const text = prompt.locator('.prompt-text');
  const action = (name: string) => prompt.getByRole('button', { name, exact: true });

  for (const [n, name, quoted, button] of [
    [1, 'Watch', `"${P1}"`, 'Send'],
    [2, 'Reminder', `"${P2}"`, 'Send'],
    [3, 'Break the feed', `"${P3}"`, 'Go to Break the feed'],
    [4, 'Approve', `"${P4}"`, 'Show me'],
  ] as const) {
    await steps.nth(n - 1).click();
    await expect(steps.nth(n - 1), `step ${n} is ${name}`).toHaveAccessibleName(new RegExp(`^Step ${n}, ${name}, `));
    await expect(text, `step ${n} shows its prompt`).toHaveText(quoted);
    await expect(action(button), `step ${n} has ${button}`).toBeVisible();
    await expect(prompt.getByRole('button'), `and no other button`).toHaveCount(1);
  }

  await steps.nth(4).click();
  await expect(text, 'step 5 shows its prompt').toHaveText(`"${P5}"`);
  await expect(prompt.getByRole('button').or(prompt.getByRole('link')), 'with Open the trace absent until the run has an incident').toHaveCount(0);
  expect(posted, 'nothing was sent').toEqual([]);
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});

/** The floor of the Break the feed box (UJ-1 step 3, Story 4.4): it is marked "Demo control", and on a fresh install its button is inactive with the not-watching hint. */
test('Break the feed is marked as a demo control', { tag: '@floor' }, async ({ page }) => {
  const violations = watchViolations(page);

  await signInReadme(page);

  await expect(page.locator('main.main')).toHaveAttribute('data-snapshot', 'loaded');
  const box = page.locator('app-break-feed-box');
  await expect(box.getByText('Demo control', { exact: true })).toBeVisible();
  const button = box.getByRole('button', { name: 'Break the feed', exact: true });
  await expect(button, 'the button is inactive (aria-disabled, never disabled)').toHaveAttribute('aria-disabled', 'true');
  await expect(button).not.toHaveAttribute('disabled', /.*/);
  await expect(button, 'with its not-watching hint as its description').toHaveAccessibleDescription('Ask OcuTalon to watch the Orders production first (step 1).');
  await expect(box.locator('.hint')).toHaveText('Ask OcuTalon to watch the Orders production first (step 1).');
  expect(violations, 'no Content-Security-Policy violation and no page error').toEqual([]);
});
