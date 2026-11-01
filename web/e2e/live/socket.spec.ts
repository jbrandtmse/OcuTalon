import { expect, test, type APIRequestContext, type Page, type PlaywrightWorkerArgs, type Route } from '@playwright/test';

import { envelope, signIn, signInOverHttp, stackOrigin } from '../sign-in/helpers';
import { STATE } from '../support/api';
import { freeze } from '../support/clock';
import { loadedAfter } from '../support/floor';
import { chk, fixtureUser, irisScript, publishReminder } from '../support/iris';
import { recordAnnouncements, announcementCount } from '../support/page';
import { blockLiveSocket, proxyLiveSocket, rawUpgrade, socketFrames, type RawUpgrade } from '../support/socket';

/**
 * Story 31.1, the live-events WebSocket (W1 to W9), in a real browser against a real stack, signed in as the live fixture user
 * (OCUTALON_LIVE_USER). The polling stays the contract and runs beside the socket; where a case needs the socket to be the only
 * path that brings an event, the page's polls are answered with their events stripped. A case publishes only on the live user's own
 * stream and reads the page's cursor fresh. W5 to W8 open sockets by hand (rawUpgrade) to send the Origin and the cookie of their own.
 */
const POLLS = /\/ocutalon\/api\/v1\/events\?/;
const END = '/ocutalon/api/v1/session/end';
const SOCKET = '/ocutalon/OcuTalon.Web.Live.cls';

type Json = Record<string, unknown>;

const mainOf = (page: Page) => page.locator('main.main');
const railOf = (page: Page) => page.locator('section.rail');
const connectionBanners = (page: Page) => page.locator('app-banner-stack [data-banner="reconnecting"], app-banner-stack [data-banner="unreachable"]');

/** A text that no other case or run publishes. */
const unique = (label: string): string => `zz socket ${label} ${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** Signs the live user in and waits until the page has loaded its snapshot. */
async function open(page: Page): Promise<void> {
  const { user, password } = fixtureUser('LIVE');
  await loadedAfter(page, () => signIn(page, user, password));
}

/** Answers every poll of the page with its events taken out, so that only the socket can bring an event. */
async function stripPollEvents(page: Page): Promise<void> {
  await page.route(POLLS, async (route: Route) => {
    const response = await route.fetch();
    const body = (await response.json()) as Json;
    await route.fulfill({ response, json: { ...body, events: [] } });
  });
}

/** The page's session cursor, as it shows it. */
async function sessionCursor(page: Page): Promise<number> {
  return Number(await mainOf(page).getAttribute('data-session-seq'));
}

/** Publishes a reminder with a text of its own on the live user's stream; the Seq and the text come back. */
async function publish(label: string, ref?: string, text = unique(label)): Promise<{ seq: number; text: string }> {
  const { user } = fixtureUser('LIVE');
  const seq = await publishReminder(user, ref === undefined ? { text } : { text, ref });
  return { seq, text };
}

/** The events of the frames that carry any, as {seq, stream}. */
function framedEvents(frames: Array<{ text: string }>): Array<{ seq: number; stream: string }> {
  return frames.flatMap((frame) => {
    const body = JSON.parse(frame.text) as { events?: Array<{ seq: number; stream: string }> };
    return (body.events ?? []).map((event) => ({ seq: event.seq, stream: event.stream }));
  });
}

/** The Ref of the live user's session row. */
async function liveRef(): Promise<string> {
  const { user } = fixtureUser('LIVE');
  const lines = await irisScript([`Set s=##class(OcuTalon.Data.Session).ForUser("${user}",.sc)`, 'Write !,"CHK|ref|",s.Ref'].join('\n'));
  const ref = chk(lines, 'ref');
  expect(ref, 'the live user has a session row').toMatch(/^[A-Za-z0-9_-]{22}$/);
  return ref!;
}

/** A signed-in HTTP client of the live user and its Cookie header. */
async function signedIn(playwright: PlaywrightWorkerArgs['playwright'], baseURL: string): Promise<{ context: APIRequestContext; cookie: string }> {
  const { user, password } = fixtureUser('LIVE');
  const context = await playwright.request.newContext({ baseURL });
  await signInOverHttp(context, user, password);
  const cookies = (await context.storageState()).cookies;
  return { context, cookie: cookies.map((one) => `${one.name}=${one.value}`).join('; ') };
}

/** The cursors of the session as a signed-in client sees them, as the query of a socket's address. */
async function cursorQuery(context: APIRequestContext): Promise<string> {
  const response = await context.get(STATE);
  expect(response.status(), 'the snapshot is served').toBe(200);
  const snapshot = (await response.json()) as { streams: { session: number; instance: number } };
  return `after=${snapshot.streams.session}&afterInstance=${snapshot.streams.instance}`;
}

/** Waits up to ms for the condition, in 100 ms looks. */
async function within(ms: number, condition: () => boolean): Promise<boolean> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (condition()) return true;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return condition();
}

/** Warms a page's socket: publishes a reminder and waits until the socket has brought it (the polls are event-free). */
async function warm(page: Page): Promise<void> {
  const { seq, text } = await publish('warm');
  await expect(railOf(page).getByText(text), 'the socket serves the first event').toBeVisible({ timeout: 15_000 });
  expect(await sessionCursor(page)).toBe(seq);
}

/**
 * W1 (AC 3, AC 4): with every poll answered event-free, a published reminder shows on the page within 2 s of the publish returning, no
 * banner shows, its Seq is in a frame the page's socket received, and no frame holds the CSP session cookie's value or the session's Ref.
 */
test('W1: an event published while the socket is open reaches the page through it, with no poll carrying it', async ({ page }) => {
  const received = socketFrames(page);
  await stripPollEvents(page);
  await open(page);
  await warm(page);

  const started = Date.now();
  const { seq, text } = await publish('w1');
  const returned = Date.now();
  await expect(railOf(page).getByText(text)).toBeVisible({ timeout: 2000 });
  const shown = Date.now();
  await expect(mainOf(page)).toHaveAttribute('data-session-seq', String(seq));
  const framedAt = received.frames.find((frame) => frame.text.includes(`"seq":${seq},`))?.at ?? 0;
  console.log(`W1: event ${seq}: frame seen ${framedAt - started} ms after the publish began, shown ${shown - returned} ms after publishReminder returned (inference)`);

  expect(framedEvents(received.frames).filter((event) => event.seq === seq && event.stream === 'session'), 'a received frame holds the event').toHaveLength(1);
  const joined = received.frames.map((frame) => frame.text).join('\n');
  const ref = await liveRef();
  expect(joined, 'no frame holds the session Ref').not.toContain(ref);
  for (const cookie of await page.context().cookies()) {
    expect(joined, `no frame holds the value of the cookie ${cookie.name}`).not.toContain(cookie.value);
  }
  await expect(connectionBanners(page)).toHaveCount(0);
});

/** W2 (AC 3): with the socket blocked, the polls bring the event within 2 s, and nothing shows. */
test('W2: with the socket blocked, polling delivers the event within 2 seconds and no banner shows', async ({ page }) => {
  await recordAnnouncements(page);
  await blockLiveSocket(page);
  await open(page);
  const before = await announcementCount(page);
  const { seq, text } = await publish('w2');
  await expect(railOf(page).getByText(text)).toBeVisible({ timeout: 2000 });
  await expect(mainOf(page)).toHaveAttribute('data-session-seq', String(seq));
  await expect(connectionBanners(page)).toHaveCount(0);
  expect(await announcementCount(page) - before, 'no live-region text for the socket or its block, beyond the event\'s own').toBeLessThanOrEqual(1);
});

/** W3: the page opens the socket at the shell's address with the cursors it holds. */
test('W3: the socket opens at the shell address with the page cursors', async ({ page }) => {
  const received = socketFrames(page);
  await open(page);
  await expect.poll(() => received.urls.length, { timeout: 15_000 }).toBeGreaterThanOrEqual(1);
  const url = new URL(received.urls[0]!);
  expect(url.pathname).toBe(SOCKET);
  expect(url.protocol).toBe(new URL(stackOrigin()).protocol === 'https:' ? 'wss:' : 'ws:');
  expect(url.host).toBe(new URL(stackOrigin()).host);
  expect(url.searchParams.get('after')).toBe(await mainOf(page).getAttribute('data-session-seq'));
  expect(url.searchParams.get('afterInstance')).toBe(await mainOf(page).getAttribute('data-instance-seq'));
});

/**
 * W4 (U-174 (c), page side): the socket is closed from outside; the page opens another with its current cursors, a publish arrives
 * through it while the polls are event-free, and neither a banner nor a live-region text shows.
 */
test('W4: a closed socket is reopened in the background with the current cursors, and delivers', async ({ page }) => {
  await recordAnnouncements(page);
  const sockets = await proxyLiveSocket(page);
  await stripPollEvents(page);
  await open(page);
  await expect.poll(() => sockets.urls.length, { timeout: 15_000 }).toBe(1);
  await warm(page);
  const cursor = await sessionCursor(page);
  const spoken = await announcementCount(page);

  await sockets.close(0);
  await expect.poll(() => sockets.urls.length, { timeout: 15_000, message: 'the page opened a second socket' }).toBe(2);
  expect(new URL(sockets.urls[1]!).searchParams.get('after'), "with the page's current cursor").toBe(String(cursor));

  const { seq, text } = await publish('w4');
  await expect(railOf(page).getByText(text), 'the second socket delivers').toBeVisible({ timeout: 15_000 });
  await expect(mainOf(page)).toHaveAttribute('data-session-seq', String(seq));
  await expect(connectionBanners(page)).toHaveCount(0);
  expect(await announcementCount(page), 'no new live-region text').toBe(spoken);
});

/** W5 (U-174 (a)): an upgrade with the right cookie and the wrong Origin, or with none, gets no data frame. */
test('W5: a wrong or missing Origin gets no frame', async ({ playwright, baseURL }) => {
  await publish('w5');
  const { context, cookie } = await signedIn(playwright, baseURL!);
  const wrong = await rawUpgrade({ baseURL: baseURL!, path: `${SOCKET}?after=0&afterInstance=0`, origin: 'http://evil.example', cookie, wait: 1500 });
  const none = await rawUpgrade({ baseURL: baseURL!, path: `${SOCKET}?after=0&afterInstance=0`, cookie, wait: 1500 });
  const right = await rawUpgrade({ baseURL: baseURL!, path: `${SOCKET}?after=0&afterInstance=0`, origin: stackOrigin(), cookie, wait: 1500 });
  try {
    await within(3000, () => right.frames.length > 0);
    expect(right.frames.length, 'control: the right Origin gets the events after cursor 0').toBeGreaterThan(0);
    expect(wrong.frames, 'the wrong Origin gets no frame').toEqual([]);
    expect(none.frames, 'no Origin gets no frame').toEqual([]);
  } finally {
    wrong.close();
    none.close();
    right.close();
    await context.dispose();
  }
});

/** W6 (U-174 (a)): an upgrade with no cookie gets no data frame. */
test('W6: an upgrade with no session gets no frame', async ({ baseURL }) => {
  await publish('w6');
  const bare = await rawUpgrade({ baseURL: baseURL!, path: `${SOCKET}?after=0&afterInstance=0`, origin: stackOrigin(), wait: 1500 });
  try {
    await new Promise((resolve) => setTimeout(resolve, 3000));
    expect(bare.frames, 'no cookie, no frame').toEqual([]);
  } finally {
    bare.close();
  }
});

/** W7 (U-174 (b)): Sign out closes the page's own socket within a poll, and no new one opens. */
test('W7: Sign out closes the socket within 2 seconds and the page opens no other', async ({ page }) => {
  const { user } = fixtureUser('LIVE');
  let opened = 0;
  let closed = 0;
  page.on('websocket', (socket) => {
    if (!socket.url().includes('OcuTalon.Web.Live.cls')) return;
    opened += 1;
    socket.on('close', () => (closed += 1));
  });
  // The page's own leaving is held back, so that only the page's Sign out can close the socket.
  await page.route(/\/ocutalon\/\?signedOut=1/, (route) => route.abort('aborted'));
  await open(page);
  await expect.poll(() => opened, { timeout: 15_000 }).toBe(1);
  expect(closed).toBe(0);

  await page.getByRole('button', { name: user, exact: true }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await expect.poll(() => closed, { timeout: 2000, message: 'the socket closed with the sign-out' }).toBe(1);
  await page.waitForTimeout(4000);
  expect(opened, 'and no new socket opened').toBe(1);
});

/**
 * W8 (U-174 sign-out mark, DW-457): an open socket of a signed-in client; the client signs out (the API's POST, then the IRISLogout
 * address). An event published afterwards reaches no data frame, and a close frame comes within 1 s of the answer.
 */
for (const how of ['POST /v1/session/end', 'GET /?IRISLogout=end'] as const) {
  test(`W8: after ${how} the socket sends no further frame and closes within a second`, async ({ playwright, baseURL }) => {
    const { context, cookie } = await signedIn(playwright, baseURL!);
    const query = await cursorQuery(context);
    const upgrade: RawUpgrade = await rawUpgrade({ baseURL: baseURL!, path: `${SOCKET}?${query}`, origin: stackOrigin(), cookie, wait: 5000 });
    try {
      expect(upgrade.status, 'the upgrade is accepted').toContain('101');
      await publish('w8 warm');
      expect(await within(15_000, () => upgrade.frames.length > 0), 'the open socket serves an event').toBe(true);
      const framesBefore = upgrade.frames.length;

      const ended =
        how === 'POST /v1/session/end'
          ? await context.post(END, { headers: envelope(), data: '{}' })
          : await context.get('/ocutalon/?IRISLogout=end');
      const answeredAt = Date.now();
      expect(ended.status(), 'the sign-out is answered').toBe(how === 'POST /v1/session/end' ? 204 : 200);

      await publish('w8 after');
      expect(await within(1000, () => upgrade.closeFrameAt > 0 || upgrade.ended), 'the socket closes within a second').toBe(true);
      await new Promise((resolve) => setTimeout(resolve, 3000));
      expect(upgrade.frames.length, 'no data frame follows the sign-out').toBe(framesBefore);
      if (upgrade.closeFrameAt > 0) expect(upgrade.closeFrameAt - answeredAt, 'the close frame comes within a second of the answer').toBeLessThan(1500);
    } finally {
      upgrade.close();
      await context.dispose();
    }
  });
}

/**
 * W9 (U-173, AC 6): one event by socket and again, late, by a poll. The page's next poll is held; "first" (Seq s+1) is published and
 * the held poll is fetched now, so its answer holds s+1 only; the socket brings "first", then "second" (s+2, the same ref); the held
 * answer is delivered last. The page still shows "second", its cursor is s+2 and it asked for no snapshot. The page's clock is
 * stopped during the hold (the contact watch counts on it) and moved in small steps for the page to render.
 */
test('W9: an event that arrives by socket and again in a late poll is applied once, by Seq', async ({ page }) => {
  await page.clock.install();
  let states = 0;
  page.on('request', (request) => {
    if (new URL(request.url()).pathname === STATE) states += 1;
  });
  let held: Route | undefined;
  let capture = false;
  await page.route(POLLS, async (route) => {
    if (capture && held === undefined) {
      held = route;
      return;
    }
    await route.continue();
  });
  await open(page);
  const look = async (read: () => Promise<boolean>, message: string): Promise<void> => {
    await expect
      .poll(
        async () => {
          await page.clock.runFor(100);
          return read();
        },
        { message, timeout: 20_000 },
      )
      .toBe(true);
  };
  const ref = `ZzSock9${Date.now().toString(36)}`;

  capture = true;
  await look(async () => held !== undefined, 'a poll is out and held');
  await freeze(page);
  const cursor = await sessionCursor(page);
  const statesBefore = states;

  const first = await publish('w9 first', ref, 'zz socket w9 first');
  expect(first.seq, 'the first publish is the next event of the stream').toBe(cursor + 1);
  const stale = await held!.fetch();
  await look(async () => (await railOf(page).getByText('zz socket w9 first').count()) > 0, 'the socket brings "first"');
  const second = await publish('w9 second', ref, 'zz socket w9 second');
  expect(second.seq).toBe(cursor + 2);
  await look(async () => (await railOf(page).getByText('zz socket w9 second').count()) > 0, 'the socket brings "second"');
  expect(await sessionCursor(page)).toBe(cursor + 2);

  await held!.fulfill({ response: stale });
  for (let step = 0; step < 10; step += 1) await page.clock.runFor(100);
  await page.clock.resume();
  await expect(railOf(page).getByText('zz socket w9 second'), 'the page still shows "second"').toBeVisible();
  await expect(railOf(page).getByText('zz socket w9 first'), 'and not the older view').toHaveCount(0);
  expect(await sessionCursor(page), 'the cursor is still s+2').toBe(cursor + 2);
  expect(states, 'and the page asked for no snapshot').toBe(statesBefore);
});

/**
 * W10 (AC 2, the Seq-skip row): with the polls event-free, one frame of the socket is changed on its way so that its first session
 * event is cursor + 2. The page reloads the snapshot once and takes its cursors (an event's own row is not in the snapshot, so the cursor
 * is what shows the reload; without it the cursor stays where it was).
 */
test('W10: a frame that skips a Seq reloads the snapshot once and the page takes its cursors', async ({ page }) => {
  let skip = false;
  await page.routeWebSocket(/\/ocutalon\/OcuTalon\.Web\.Live\.cls/, (socket) => {
    const server = socket.connectToServer();
    server.onMessage((message) => {
      if (!skip || typeof message !== 'string') {
        socket.send(message);
        return;
      }
      const body = JSON.parse(message) as { events: Array<{ seq: number; stream: string }> };
      if (body.events.length === 0) {
        socket.send(message);
        return;
      }
      skip = false;
      socket.send(JSON.stringify({ ...body, events: body.events.map((event) => (event.stream === 'session' ? { ...event, seq: event.seq + 1 } : event)) }));
    });
  });
  await stripPollEvents(page);
  await open(page);
  await warm(page);

  let states = 0;
  page.on('request', (request) => {
    if (new URL(request.url()).pathname === STATE) states += 1;
  });
  skip = true;
  const { seq } = await publish('w10');
  await expect(mainOf(page), "the reloaded snapshot's cursor replaces the old one").toHaveAttribute('data-session-seq', String(seq), { timeout: 15_000 });
  await page.waitForTimeout(1500);
  expect(states, 'one snapshot reload').toBe(1);
  await expect(connectionBanners(page)).toHaveCount(0);
});

/** The IRIS processes, as {pid, routine}: the routine each one is running now. */
async function processes(): Promise<Array<{ pid: string; routine: string }>> {
  const lines = await irisScript(
    ['Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Pid, Routine FROM %SYS.ProcessQuery") Set r="" For { Quit:\'rs.%Next()  Set r=r_rs.%Get("Pid")_"="_rs.%Get("Routine")_";" }', 'Write !,"CHK|processes|",r'].join('\n'),
  );
  return (chk(lines, 'processes') ?? '')
    .split(';')
    .filter((one) => one !== '')
    .map((one) => ({ pid: one.slice(0, one.indexOf('=')), routine: one.slice(one.indexOf('=') + 1) }));
}

/** The pids of the IRIS processes that are running the live socket's class now. */
async function socketPids(): Promise<string[]> {
  return (await processes()).filter((one) => one.routine.includes('OcuTalon.Web.Live')).map((one) => one.pid);
}

/** Looks until the condition holds or ms have passed. */
async function eventually(ms: number, condition: () => Promise<boolean>): Promise<boolean> {
  const deadline = Date.now() + ms;
  for (;;) {
    if (await condition()) return true;
    if (Date.now() >= deadline) return false;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

/**
 * W11 (the Client-closes row): a close frame from the client ends the server's loop, which ends the IRIS process of the socket at once
 * (a process that the gateway's closed connection reaches instead stays for the 5 seconds of the platform's read-error path), and the
 * connection ends within a second.
 */
test('W11: a close frame from the client ends the socket and its server process within two seconds', async ({ playwright, baseURL }) => {
  const { context, cookie } = await signedIn(playwright, baseURL!);
  const query = await cursorQuery(context);
  await eventually(5000, async () => (await socketPids()).length === 0);
  const before = await socketPids();
  const upgrade: RawUpgrade = await rawUpgrade({ baseURL: baseURL!, path: `${SOCKET}?${query}`, origin: stackOrigin(), cookie, wait: 5000 });
  try {
    expect(upgrade.status, 'the upgrade is accepted').toContain('101');
    await publish('w11 warm');
    expect(await within(15_000, () => upgrade.frames.length > 0), 'the open socket serves an event').toBe(true);
    let mine: string[] = [];
    expect(
      await eventually(3000, async () => {
        mine = (await socketPids()).filter((pid) => !before.includes(pid));
        return mine.length > 0;
      }),
      `the server runs a process for the socket (processes: ${(await processes()).map((one) => `${one.pid}=${one.routine}`).join(',')})`,
    ).toBe(true);

    upgrade.sendClose();
    expect(await within(1000, () => upgrade.closeFrameAt > 0 || upgrade.ended), 'the connection ends within a second of the close frame').toBe(true);
    expect(await eventually(2000, async () => !(await processes()).some((one) => mine.includes(one.pid))), "and the socket's process has ended").toBe(true);
  } finally {
    upgrade.close();
    await context.dispose();
  }
});

/**
 * W12 (the Quiet-socket row, and AC 5's lifetime): a socket with nothing to send gets a heartbeat frame {epoch, events: []} after
 * about 25 s, and the server ends it with a close frame at its 60 s lifetime.
 */
test('W12: a quiet socket gets a heartbeat, and the server ends it at its lifetime', async ({ playwright, baseURL }) => {
  test.setTimeout(150_000);
  const { context, cookie } = await signedIn(playwright, baseURL!);
  const query = await cursorQuery(context);
  const startedAt = Date.now();
  const upgrade: RawUpgrade = await rawUpgrade({ baseURL: baseURL!, path: `${SOCKET}?${query}`, origin: stackOrigin(), cookie, wait: 5000 });
  try {
    expect(upgrade.status, 'the upgrade is accepted').toContain('101');
    expect(await within(35_000, () => upgrade.frames.length > 0), 'a heartbeat frame comes').toBe(true);
    const first = upgrade.frames[0]!;
    expect(first.at - startedAt, 'after about 25 seconds of quiet').toBeGreaterThan(20_000);
    const body = JSON.parse(first.text) as { epoch?: unknown; events?: unknown[] };
    expect(typeof body.epoch, 'it holds the epoch').toBe('string');
    expect(body.events, 'and no event').toEqual([]);

    expect(await within(50_000, () => upgrade.closeFrameAt > 0), 'the server ends the socket with a close frame').toBe(true);
    expect(upgrade.closeFrameAt - startedAt, 'at the 60 second lifetime').toBeGreaterThan(55_000);
    expect(upgrade.closeFrameAt - startedAt, 'and not much after it').toBeLessThan(70_000);
    for (const frame of upgrade.frames) {
      expect((JSON.parse(frame.text) as { events: unknown[] }).events, 'every frame of the quiet socket is a heartbeat').toEqual([]);
    }
  } finally {
    upgrade.close();
    await context.dispose();
  }
});
