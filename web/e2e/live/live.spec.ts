import { expect, test, type Page, type Route } from '@playwright/test';

import { signIn } from '../sign-in/helpers';
import { fixtureUser, publishReminder } from '../support/iris';

/**
 * Story 2.2, the live path (L1 to L8), in a real browser against a real stack, signed in as the live fixture user that
 * test-sign-in.sh created (OCUTALON_LIVE_USER). No spec here publishes on the README session's stream or the instance
 * stream, whose counts api.spec.ts pins; an event is published on the live user's own stream through the IRIS container.
 * Where a case needs the server held or failing, the page's own /state or /events answer is routed in the browser.
 */
const STATE = '/ocutalon/api/v1/state';
const EVENTS = '/ocutalon/api/v1/events';
const LOAD_FAILED = "Couldn't load your session.";
const BUSY_NOTICE = "Couldn't reach OcuTalon. Try again. Nothing was changed.";

type Json = Record<string, unknown>;

const mainOf = (page: Page) => page.locator('main.main');
const isPath = (url: string, path: string): boolean => new URL(url).pathname === path;

/** Signs the live user in and waits until the page has loaded its snapshot. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('LIVE');
  await signIn(page, user, password);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
}

/** Counts the page's requests for a path, as they are made. */
function countRequests(page: Page, path: string): () => number {
  let count = 0;
  page.on('request', (request) => {
    if (isPath(request.url(), path)) count += 1;
  });
  return () => count;
}

/** The start time (page clock, ms) and the URL of each /events request that has finished, in order. */
async function polls(page: Page): Promise<Array<{ start: number; params: URLSearchParams }>> {
  const entries = await page.evaluate(() =>
    performance
      .getEntriesByType('resource')
      .filter((entry) => entry.name.includes('/ocutalon/api/v1/events'))
      .map((entry) => ({ start: entry.startTime, url: entry.name })),
  );
  return entries.map((entry) => ({ start: entry.start, params: new URL(entry.url).searchParams }));
}

/** Holds every /state request of the page until release() is called, then lets the held ones through to the server. */
async function holdState(page: Page): Promise<{ release: () => void; held: () => number }> {
  const waiting: Array<() => void> = [];
  let released = false;
  await page.route(`**${STATE}`, async (route: Route) => {
    if (!released) {
      await new Promise<void>((resolve) => waiting.push(resolve));
    }
    await route.continue().catch(() => undefined);
  });
  return {
    release: () => {
      released = true;
      for (const resolve of waiting.splice(0)) resolve();
    },
    held: () => waiting.length,
  };
}

/**
 * Before the page's scripts run: records every text that the polite announcer's live region receives (each node added to
 * it), as window.announced, so a test can count how often a message was announced.
 */
async function recordAnnouncements(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const announced: string[] = [];
    (window as unknown as { announced: string[] }).announced = announced;
    new MutationObserver((records) => {
      for (const record of records) {
        if (!(record.target instanceof HTMLElement) || !record.target.classList.contains('cdk-live-announcer-element')) continue;
        for (const node of Array.from(record.addedNodes)) {
          if (node.textContent) announced.push(node.textContent);
        }
      }
    }).observe(document, { subtree: true, childList: true });
  });
}

const announcements = (page: Page, text: string): Promise<number> =>
  page.evaluate((wanted) => (window as unknown as { announced: string[] }).announced.filter((entry) => entry === wanted).length, text);

/** The computed colour of a token, as the page paints it. */
function tokenColor(page: Page, token: string): Promise<string> {
  return page.evaluate((name) => {
    const probe = document.createElement('span');
    probe.style.color = `var(${name})`;
    document.body.append(probe);
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  }, token);
}

/** L1: one /state, then a poll every 1 to 2 seconds, each with the cursors that the page holds. */
test('L1: /state is requested once, and polls come every 1 to 2 seconds with the current cursors', async ({ page }) => {
  const states = countRequests(page, STATE);
  const answered = page.waitForResponse((response) => isPath(response.url(), STATE));
  await open(page);
  const snapshot = (await (await answered).json()) as { streams: { session: number; instance: number } };
  await expect(mainOf(page)).toHaveAttribute('data-session-seq', String(snapshot.streams.session));
  await expect(mainOf(page)).toHaveAttribute('data-instance-seq', String(snapshot.streams.instance));

  await expect.poll(async () => (await polls(page)).length, { timeout: 20_000 }).toBeGreaterThanOrEqual(4);
  const seen = await polls(page);
  for (const [i, poll] of seen.entries()) {
    expect(poll.params.get('after'), `poll ${i} carries the session cursor`).toBe(String(snapshot.streams.session));
    expect(poll.params.get('afterInstance'), `poll ${i} carries the instance cursor`).toBe(String(snapshot.streams.instance));
  }
  for (let i = 1; i <= 3; i += 1) {
    const gap = seen[i]!.start - seen[i - 1]!.start;
    expect(gap, `the interval before poll ${i}`).toBeGreaterThanOrEqual(1000);
    expect(gap, `the interval before poll ${i}`).toBeLessThanOrEqual(2000);
  }
  expect(states(), '/state was requested once').toBe(1);
});

/**
 * L2: an event published on the session's stream is on the page within 2 s, with no reload and no navigation, and the next
 * poll carries the advanced cursor.
 */
test('L2: an event published after the load is applied within 2 seconds, with no reload', async ({ page }) => {
  const states = countRequests(page, STATE);
  await open(page);
  await page.evaluate(() => ((window as unknown as { marker: string }).marker = 'kept'));
  const url = page.url();

  const { user } = fixtureUser('LIVE');
  const seq = await publishReminder(user);
  const returned = Date.now();
  const advanced = page.waitForRequest((request) => isPath(request.url(), EVENTS) && new URL(request.url()).searchParams.get('after') === String(seq), { timeout: 4000 });
  advanced.catch(() => undefined);
  await expect(mainOf(page)).toHaveAttribute('data-session-seq', String(seq), { timeout: 2000 });
  const elapsed = Date.now() - returned;
  console.log(`L2: event ${seq} applied ${elapsed} ms after publishReminder returned`);
  await advanced;

  expect(await page.evaluate(() => (window as unknown as { marker: string }).marker), 'the page was not reloaded').toBe('kept');
  expect(page.url(), 'and did not navigate').toBe(url);
  expect(states(), 'and /state was requested once').toBe(1);
});

/**
 * L3: the answer of one real poll is changed in the browser. An event two past the cursor makes the page load the
 * snapshot again, once, and the page stays loaded; an event at the cursor (a repeat) changes nothing and asks for nothing.
 */
test('L3: a Seq that skips reloads the snapshot once, and the page stays loaded', async ({ page }) => {
  const states = countRequests(page, STATE);
  let injected = false;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    if (injected) {
      await route.fulfill({ response });
      return;
    }
    injected = true;
    const body = (await response.json()) as { events: Json[] };
    const after = Number(new URL(route.request().url()).searchParams.get('after'));
    body.events.push({ seq: after + 2, stream: 'session', ts: '2030-01-01T00:00:00Z', type: 'reminder', payload: { ref: 'ZzE2ESkip', state: 'pending' } });
    await route.fulfill({ response, json: body });
  });
  await page.addInitScript(() => {
    const snapshots: string[] = [];
    (window as unknown as { snapshots: string[] }).snapshots = snapshots;
    new MutationObserver((records) => {
      for (const record of records) {
        const value = (record.target as HTMLElement).getAttribute('data-snapshot');
        if (value) snapshots.push(value);
      }
    }).observe(document, { subtree: true, attributes: true, attributeFilter: ['data-snapshot'] });
  });
  await open(page);
  await expect.poll(() => states(), { timeout: 10_000 }).toBe(2);
  const snapshots = await page.evaluate(() => (window as unknown as { snapshots: string[] }).snapshots);
  expect(snapshots.slice(snapshots.indexOf('loaded')), 'data-snapshot stayed loaded from the first load on').toEqual(['loaded']);
  await page.waitForTimeout(3500);
  expect(states(), 'the snapshot was loaded again once, and not a third time').toBe(2);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
});

test('L3: a repeated event changes neither the cursor nor the snapshot', async ({ page }) => {
  const states = countRequests(page, STATE);
  let injected = 0;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as { events: Json[] };
    const after = Number(new URL(route.request().url()).searchParams.get('after'));
    if (injected < 2) {
      injected += 1;
      body.events.push({ seq: after, stream: 'session', ts: '2030-01-01T00:00:00Z', type: 'reminder', payload: { ref: 'ZzE2ERepeat', state: 'pending' } });
      body.events.push({ seq: Math.max(after - 1, 0), stream: 'session', ts: '2030-01-01T00:00:00Z', type: 'reminder', payload: { ref: 'ZzE2EOlder', state: 'pending' } });
    }
    await route.fulfill({ response, json: body });
  });
  await open(page);
  const cursor = await mainOf(page).getAttribute('data-session-seq');
  await expect.poll(() => injected, { timeout: 10_000 }).toBe(2);
  await page.waitForTimeout(2500);
  expect(await mainOf(page).getAttribute('data-session-seq'), 'the cursor did not move').toBe(cursor);
  expect(states(), 'and nothing was reloaded').toBe(1);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
});

/** L4: applying an event never moves keyboard focus. */
test('L4: focus stays where it was when an event is applied', async ({ page }) => {
  await open(page);
  const theme = page.getByRole('button', { name: 'Theme: System', exact: true });
  await theme.focus();
  await expect(theme).toBeFocused();
  await page.evaluate(() => {
    const seen = { focusins: 0 };
    (window as unknown as { seen: typeof seen }).seen = seen;
    document.addEventListener('focusin', () => (seen.focusins += 1));
  });
  const before = await page.evaluate(() => document.activeElement?.outerHTML);

  const { user } = fixtureUser('LIVE');
  const seq = await publishReminder(user);
  await expect(mainOf(page)).toHaveAttribute('data-session-seq', String(seq), { timeout: 3000 });
  await page.waitForTimeout(1500);

  expect(await page.evaluate(() => document.activeElement?.outerHTML), 'the active element is the same').toBe(before);
  await expect(theme).toBeFocused();
  expect(await page.evaluate(() => (window as unknown as { seen: { focusins: number } }).seen.focusins), 'and no element took the focus').toBe(0);
});

/** L5: while /state is out, static skeletons fill the rail sections and main, hidden from assistive technology. */
test('L5: static skeletons while the snapshot loads', async ({ page }) => {
  const hold = await holdState(page);
  try {
    const { user, password } = fixtureUser('LIVE');
    await signIn(page, user, password);
    await expect.poll(() => hold.held()).toBe(1);

    const rail = page.locator('section.rail');
    const main = mainOf(page);
    await expect(main).toHaveAttribute('data-snapshot', 'loading');
    await expect(rail).toHaveAttribute('aria-busy', 'true');
    await expect(main).toHaveAttribute('aria-busy', 'true');

    const groups = rail.locator('.skeleton-rows');
    await expect(groups, 'a group of skeleton rows in each of the four rail sections').toHaveCount(4);
    for (const group of await groups.all()) {
      await expect(group).toHaveAttribute('aria-hidden', 'true');
      await expect(group.locator('.skeleton-row'), 'two rows in a section').toHaveCount(2);
      await expect(group.locator('.skeleton-row').first().locator('.skeleton'), 'a row has title, detail and meta blocks').toHaveCount(3);
    }
    const chat = main.locator('.skeleton-chat');
    await expect(chat).toHaveAttribute('aria-hidden', 'true');
    await expect(chat.locator('.skeleton'), 'three entries in main').toHaveCount(3);
    await expect(chat.locator('.chat-bubble'), 'one of them a bubble').toHaveCount(1);
    const bubble = (await chat.locator('.chat-bubble').boundingBox())!;
    const area = (await main.boundingBox())!;
    expect(bubble.x + bubble.width, 'the bubble is at the right').toBeGreaterThan(area.x + area.width * 0.7);

    const background = await tokenColor(page, '--skeleton-background');
    for (const block of await page.locator('.skeleton').all()) {
      await expect(block).toHaveCSS('background-color', background);
      await expect(block, 'no animation').toHaveCSS('animation-name', 'none');
      await expect(block, 'no transition').toHaveCSS('transition-duration', '0s');
    }
    await expect(page.locator('app-server-button'), 'no Retry while loading').toHaveCount(0);
  } finally {
    hold.release();
  }
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.locator('.skeleton'), 'the skeletons leave with the data').toHaveCount(0);
  await expect(mainOf(page)).not.toHaveAttribute('aria-busy', 'true');
});

/** L6: with no answer in 10 s the load error and Retry replace the skeletons; Retry is busy, then restores with its notice. */
test('L6: no data by 10 seconds shows the load error with Retry, which is busy and then restores with its notice', async ({ page }) => {
  await recordAnnouncements(page);
  await page.clock.install();
  const hold = await holdState(page);
  try {
    const { user, password } = fixtureUser('LIVE');
    await signIn(page, user, password);
    await expect.poll(() => hold.held()).toBe(1);
    const main = mainOf(page);
    await expect(main).toHaveAttribute('data-snapshot', 'loading');
    await expect(page.locator('.load-error'), 'no error before 10 seconds').toHaveCount(0);

    await page.clock.runFor(10_000);
    await expect(main).toHaveAttribute('data-snapshot', 'failed');
    const error = main.locator('.load-error');
    await expect(error.locator('p')).toHaveText(LOAD_FAILED);
    await expect(page.locator('.skeleton'), 'the skeletons give way').toHaveCount(0);
    await expect(page.locator('.cdk-live-announcer-element')).toHaveText(LOAD_FAILED);
    expect(await announcements(page, LOAD_FAILED), 'announced once').toBe(1);

    const retry = error.getByRole('button', { name: 'Retry', exact: true });
    await expect(retry).toBeVisible();
    await retry.click();
    await expect.poll(() => hold.held(), { message: 'Retry asks for the snapshot again' }).toBe(2);
    await expect(retry, 'busy: aria-busy').toHaveAttribute('aria-busy', 'true');
    await expect(retry, 'and aria-disabled').toHaveAttribute('aria-disabled', 'true');
    await expect(retry, 'never disabled').not.toHaveAttribute('disabled', /.*/);
    await expect(retry, 'the label is kept').toHaveText('Retry');
    await expect(retry.locator('.spinner'), 'with a spinner').toHaveCount(1);

    await page.clock.runFor(10_000);
    await expect(retry, 'the button restores').not.toHaveAttribute('aria-busy', 'true');
    await expect(retry).not.toHaveAttribute('aria-disabled', 'true');
    const notice = error.locator('app-inline-notice');
    await expect(notice).toHaveText(BUSY_NOTICE);
    const below = (await notice.boundingBox())!;
    const button = (await retry.boundingBox())!;
    expect(below.y, 'the notice is under the button').toBeGreaterThanOrEqual(button.y + button.height);
    await expect(page.locator('.cdk-live-announcer-element')).toHaveText(BUSY_NOTICE);
    expect(await announcements(page, BUSY_NOTICE), 'the notice is announced once').toBe(1);
    expect(await announcements(page, LOAD_FAILED), 'and the load error was not announced again').toBe(1);
  } finally {
    hold.release();
  }
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.locator('.load-error'), 'a late answer removes the error').toHaveCount(0);
  await expect(page.locator('app-inline-notice')).toHaveCount(0);
});

/** L7: a fast 500 shows the error at once; a Retry that answers 500 restores the button and announces the error again. */
test('L7: an error answer shows the load error at once, and a failed Retry announces it again', async ({ page }) => {
  await recordAnnouncements(page);
  let answers = 0;
  await page.route(`**${STATE}`, async (route) => {
    answers += 1;
    await route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } } });
  });
  const { user, password } = fixtureUser('LIVE');
  await signIn(page, user, password);
  const main = mainOf(page);
  await expect(main).toHaveAttribute('data-snapshot', 'failed', { timeout: 3000 });
  await expect(main.locator('.load-error p')).toHaveText(LOAD_FAILED);
  await expect(page.locator('.skeleton')).toHaveCount(0);
  await expect.poll(() => announcements(page, LOAD_FAILED)).toBe(1);
  expect(answers, 'the snapshot was asked for once').toBe(1);

  const retry = main.getByRole('button', { name: 'Retry', exact: true });
  await retry.click();
  await expect.poll(() => announcements(page, LOAD_FAILED), { message: 'the failure is announced again' }).toBe(2);
  expect(answers, 'Retry asked again').toBe(2);
  await expect(retry, 'the button is restored').not.toHaveAttribute('aria-busy', 'true');
  await expect(retry).not.toHaveAttribute('aria-disabled', 'true');
  await expect(main).toHaveAttribute('data-snapshot', 'failed');
});

/** L8: a poll that fails (not with a 401) is asked again after the same delay, and nothing else on the page changes. */
test('L8: a failed poll is asked again after the same delay, and the page stays as it was', async ({ page }) => {
  const states = countRequests(page, STATE);
  const times: number[] = [];
  const answers: number[] = [];
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    times.push(Date.now());
    if (times.length <= 2) {
      await route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } } });
      return;
    }
    const response = await route.fetch();
    answers.push(response.status());
    await route.fulfill({ response });
  });
  await open(page);
  const cursor = await mainOf(page).getAttribute('data-session-seq');

  await expect.poll(() => answers.length, { timeout: 15_000, message: 'a poll after the two failures is answered' }).toBeGreaterThanOrEqual(1);
  expect(answers[0], 'and it is answered 200').toBe(200);
  for (let i = 1; i <= 2; i += 1) {
    const gap = times[i]! - times[i - 1]!;
    expect(gap, `the interval before poll ${i + 1}`).toBeGreaterThanOrEqual(900);
    expect(gap, `the interval before poll ${i + 1}`).toBeLessThanOrEqual(2500);
  }
  expect(states(), '/state was requested once').toBe(1);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
  expect(await mainOf(page).getAttribute('data-session-seq'), 'the cursor did not move').toBe(cursor);
  await expect(page.locator('.load-error'), 'no load error').toHaveCount(0);
  await expect(page.locator('app-inline-notice'), 'and no notice').toHaveCount(0);
});
