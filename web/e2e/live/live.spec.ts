import { expect, test, type Page, type Route } from '@playwright/test';

import { holdState } from '../support/api';
import { signIn } from '../sign-in/helpers';
import { loadedAfter } from '../support/floor';
import { freeze, lastAnswerAt, pollStarts, recordTraffic, runUntil } from '../support/clock';
import { fixtureUser, publishReminder } from '../support/iris';
import { announcements, recordAnnouncements } from '../support/page';

/**
 * Story 2.2, the live path (L1 to L13), in a real browser against a real stack, signed in as the live fixture user that
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
  await loadedAfter(page, () => signIn(page, user, password));
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

/**
 * Before the page's scripts run: records every value that the main region's data-snapshot takes, in order, as window.snapshots,
 * so a test can tell that the snapshot's status never left loaded while the snapshot was loaded again.
 */
async function recordSnapshotStates(page: Page): Promise<void> {
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
}

const snapshotStates = (page: Page): Promise<string[]> => page.evaluate(() => (window as unknown as { snapshots: string[] }).snapshots);

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
  await recordSnapshotStates(page);
  await open(page);
  await expect.poll(() => states(), { timeout: 10_000 }).toBe(2);
  const snapshots = await snapshotStates(page);
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
  expect(cursor, 'the page holds a session cursor').toMatch(/^\d+$/);
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
    await expect(page.locator('app-chat-panel, app-composer'), 'no chat panel and no composer while loading').toHaveCount(0);
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
  await expect(page.locator('app-chat-panel, app-composer'), 'no chat panel and no composer after a failed load').toHaveCount(0);
  await expect(page.locator('section.rail h3'), 'the rail keeps its four plain headings after a failed load').toHaveText([
    'Approval requests',
    'Background checks',
    'Reminders',
    'Recent decisions',
  ]);
  await expect(page.locator('app-status-rail'), 'and holds no status rail').toHaveCount(0);
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
  expect(cursor, 'the page holds a session cursor').toMatch(/^\d+$/);

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

/**
 * L9: a poll answered with an epoch that is not the snapshot's (the session was reset on the server) loads the snapshot
 * again, once, and the page stays loaded; the polls that follow carry the epoch of the new snapshot and ask for nothing more.
 */
test("L9: an epoch that is not the snapshot's loads the snapshot again once, and the page stays loaded", async ({ page }) => {
  const states = countRequests(page, STATE);
  let changed = false;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    if (changed) {
      await route.fulfill({ response });
      return;
    }
    changed = true;
    const body = (await response.json()) as Json;
    body['epoch'] = 'ZzE2EOtherEpoch';
    await route.fulfill({ response, json: body });
  });
  await recordSnapshotStates(page);
  await open(page);
  await expect.poll(() => states(), { timeout: 10_000, message: 'the other epoch loads the snapshot again' }).toBe(2);
  const polled = (await polls(page)).length;
  await expect.poll(async () => (await polls(page)).length, { timeout: 15_000, message: 'three more polls follow the reload' }).toBeGreaterThanOrEqual(polled + 3);
  expect(states(), 'and none of them loads the snapshot a third time').toBe(2);
  const snapshots = await snapshotStates(page);
  expect(snapshots.slice(snapshots.indexOf('loaded')), 'data-snapshot stayed loaded from the first load on').toEqual(['loaded']);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
});

/**
 * L10: an event is lost on the way (the answer of one poll holds a later event but not the next one): the snapshot is loaded
 * again, and its cursors replace the old ones, so the first poll after the reload asks from the new snapshot's cursor and the
 * page does not fetch the event it already holds again.
 */
test("L10: after a skip the reloaded snapshot's cursors replace the old ones", async ({ page }) => {
  const states = countRequests(page, STATE);
  const asked: string[] = [];
  let armed = false;
  let lostAt = -1;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    const response = await route.fetch();
    const after = new URL(route.request().url()).searchParams.get('after') ?? '';
    asked.push(after);
    const body = (await response.json()) as { events: Json[] };
    const next = body.events.find((event) => event['stream'] === 'session' && event['seq'] === Number(after) + 1);
    if (!armed || !next) {
      await route.fulfill({ response });
      return;
    }
    armed = false;
    lostAt = asked.length - 1;
    body.events = body.events.filter((event) => event !== next);
    body.events.push({ seq: Number(after) + 2, stream: 'session', ts: '2030-01-01T00:00:00Z', type: 'reminder', payload: { ref: 'ZzE2ELost', state: 'pending' } });
    await route.fulfill({ response, json: body });
  });
  await recordSnapshotStates(page);
  await open(page);
  const cursor = Number(await mainOf(page).getAttribute('data-session-seq'));

  armed = true;
  const { user } = fixtureUser('LIVE');
  const seq = await publishReminder(user);
  expect(seq, 'the published event is the next one of the stream').toBe(cursor + 1);
  await expect.poll(() => lostAt, { timeout: 10_000, message: 'a poll answered with a skip' }).toBeGreaterThanOrEqual(0);
  await expect.poll(() => states(), { timeout: 10_000, message: 'the skip loads the snapshot again' }).toBe(2);
  await expect(mainOf(page), "the new snapshot's cursor is the page's").toHaveAttribute('data-session-seq', String(seq));
  await expect.poll(() => asked.length, { timeout: 10_000, message: 'a poll after the reload' }).toBeGreaterThan(lostAt + 1);
  expect(asked[lostAt + 1], "the first poll after the reload carries the new snapshot's cursor").toBe(String(seq));
  expect(states(), 'and the snapshot was loaded once more only').toBe(2);
  const snapshots = await snapshotStates(page);
  expect(snapshots.slice(snapshots.indexOf('loaded')), 'data-snapshot stayed loaded').toEqual(['loaded']);
});

/**
 * L11: a Retry that /state answers loads the page: while it waits the button is busy, then the error and the button give way
 * to the page, the failure is not announced again, no notice shows, and the polling starts.
 */
test('L11: a Retry that is answered loads the page, with no notice and no second announcement', async ({ page }) => {
  await recordAnnouncements(page);
  let answers = 0;
  let release: () => void = () => undefined;
  const released = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route(`**${STATE}`, async (route) => {
    answers += 1;
    if (answers === 1) {
      await route.fulfill({ status: 500, json: { error: { code: 'server_error', message: 'Something went wrong inside OcuTalon. Try again.' } } });
      return;
    }
    await released;
    await route.continue().catch(() => undefined);
  });
  try {
    const { user, password } = fixtureUser('LIVE');
    await signIn(page, user, password);
    const main = mainOf(page);
    await expect(main).toHaveAttribute('data-snapshot', 'failed', { timeout: 3000 });
    await expect.poll(() => announcements(page, LOAD_FAILED)).toBe(1);

    const retry = main.getByRole('button', { name: 'Retry', exact: true });
    await retry.click();
    await expect.poll(() => answers, { message: 'Retry asks for the snapshot again' }).toBe(2);
    await expect(retry, 'busy while it waits').toHaveAttribute('aria-busy', 'true');
    await expect(retry.locator('.spinner'), 'with a spinner').toHaveCount(1);
    await expect(main, 'and the page is still the load error').toHaveAttribute('data-snapshot', 'failed');
  } finally {
    release();
  }
  const main = mainOf(page);
  await expect(main, 'the answer loads the page').toHaveAttribute('data-snapshot', 'loaded');
  await expect(page.locator('.load-error'), 'the error is gone').toHaveCount(0);
  await expect(page.locator('.skeleton'), 'and there is no skeleton').toHaveCount(0);
  await expect(page.locator('app-inline-notice'), 'no notice shows').toHaveCount(0);
  await expect(main, 'the page holds the snapshot cursors').toHaveAttribute('data-session-seq', /^\d+$/);
  await expect.poll(async () => (await polls(page)).length, { timeout: 10_000, message: 'the polling starts' }).toBeGreaterThan(0);
  expect(await announcements(page, LOAD_FAILED), 'the failure was announced once').toBe(1);
  expect(await announcements(page, BUSY_NOTICE), 'and the busy notice not at all').toBe(0);
});

/**
 * L12: one poll at a time. While a poll's answer is held, no other /events request starts; the next one starts about
 * POLL_DELAY_MS (1 s) after the held answer arrives.
 */
test('L12: a poll whose answer is slow is the only one in flight, and the next waits for its answer', async ({ page }) => {
  const starts: number[] = [];
  let release: () => void = () => undefined;
  const released = new Promise<void>((resolve) => {
    release = resolve;
  });
  let answeredAt = 0;
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    starts.push(Date.now());
    if (starts.length === 2) {
      await released;
      answeredAt = Date.now();
    }
    await route.continue().catch(() => undefined);
  });
  try {
    await open(page);
    await expect.poll(() => starts.length, { timeout: 10_000, message: 'the second poll starts and is held' }).toBe(2);
    await page.waitForTimeout(3000);
    expect(starts.length, 'no other poll starts while one is out').toBe(2);
  } finally {
    release();
  }
  await expect.poll(() => starts.length, { timeout: 5000, message: 'the next poll follows the answer' }).toBe(3);
  const gap = starts[2]! - answeredAt;
  expect(gap, 'the next poll waits the delay after the answer').toBeGreaterThanOrEqual(900);
  expect(gap, 'the next poll waits the delay after the answer').toBeLessThanOrEqual(2500);
  await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
});

/**
 * L13: a poll that never answers is given up after POLL_TIMEOUT_MS (10 s), and the next poll follows after the usual delay,
 * so the live updates go on. The page counts its 10 s of silence from its last answer, so Reconnecting shows while the poll is
 * still out, and the next answer clears it (Story 2.11); nothing else on the page changes. The page's clock is Playwright's, stopped
 * for the two checks on either side of the 10 s of silence (at 9 s, and at 10.5 s, before the poll is given up at 11 s), so that a slow
 * host cannot move the page past the poll's end; the times of the polls are read from that clock.
 */
test('L13: a poll that never answers is given up after 10 seconds, and the polling goes on', async ({ page }) => {
  const states = countRequests(page, STATE);
  let started = 0;
  const held: Route[] = [];
  await recordTraffic(page);
  await page.clock.install();
  await page.route(/\/ocutalon\/api\/v1\/events\?/, async (route) => {
    started += 1;
    if (started === 2) {
      held.push(route);
      return;
    }
    await route.continue().catch(() => undefined);
  });
  try {
    await open(page);
    await expect.poll(() => started, { timeout: 10_000, message: 'the second poll starts and gets no answer' }).toBe(2);
    const reconnecting = page.locator('.banner-slot [data-banner="reconnecting"]');
    await freeze(page);
    const heard = await lastAnswerAt(page);
    await runUntil(page, heard, 9_000);
    await expect(reconnecting, 'no banner 9 s after the last answer, while the poll is out').toHaveCount(0);
    await runUntil(page, heard, 10_500);
    await expect(reconnecting, '10 s after the last answer Reconnecting shows').toHaveCount(1);
    expect(started, 'while the second poll has still had no answer').toBe(2);
    await page.clock.resume();
    await expect.poll(() => started, { timeout: 15_000, message: 'a poll follows the one that never answered' }).toBe(3);
    const at = await pollStarts(page);
    const gap = at[2]! - at[1]!;
    expect(gap, 'it is given up after 10 s, then the delay').toBeGreaterThanOrEqual(10_900);
    expect(gap, 'it is given up after 10 s, then the delay').toBeLessThanOrEqual(13_000);
    await expect.poll(() => started, { timeout: 5000, message: 'and the polling goes on' }).toBeGreaterThanOrEqual(4);
    await expect(reconnecting, 'the next answer clears Reconnecting').toHaveCount(0);
    expect(states(), '/state was requested once').toBe(1);
    await expect(mainOf(page)).toHaveAttribute('data-snapshot', 'loaded');
    await expect(page.locator('.load-error'), 'no load error').toHaveCount(0);
  } finally {
    for (const route of held) await route.abort().catch(() => undefined);
  }
});
