import { expect, test, type APIRequestContext, type APIResponse, type Page, type Route } from '@playwright/test';

import { envelope } from '../sign-in/helpers';
import { freeze } from './clock';

/**
 * What the API specs share: the three routes a spec polls and posts to, one live event as /events serves it, and the two calls that
 * post a message the way the page does and wait for the session stream. api.spec.ts (Story 2.4), trace.spec.ts (Story 2.9) and links.spec.ts (Story 2.13) use them.
 * frame.spec.ts (Story 2.1) and links.spec.ts also answer the page's /state with a changed copy of the real answer (changeSnapshot).
 * The floor specs (Story 2.12) hold one poll, with the page's clock stopped, so that what a case seeds reaches the page in a single update (holdPoll).
 * live.spec.ts and the floor specs of Story 2.14 hold the page's /state requests until a release (holdState).
 */

export const STATE = '/ocutalon/api/v1/state';
export const EVENTS = '/ocutalon/api/v1/events';
export const MESSAGES = '/ocutalon/api/v1/messages';

/** One live event of a poll. */
export interface LiveEvent {
  seq: number;
  stream: string;
  type: string;
  payload: Record<string, unknown>;
}

/** Answers the page's /state with the real server's answer, changed by `change`. Call it before signing in. */
export async function changeSnapshot(page: Page, change: (snapshot: Record<string, unknown>) => void): Promise<void> {
  await page.route(`**${STATE}`, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as Record<string, unknown>;
    change(body);
    await route.fulfill({ response, json: body });
  });
}

/** Posts a body as the page does: the whole browser envelope and the JSON text of data. */
export function post(request: APIRequestContext, path: string, data: unknown): Promise<APIResponse> {
  return request.fetch(path, { method: 'POST', headers: envelope(), data: typeof data === 'string' ? data : JSON.stringify(data) });
}

/**
 * The session stream's events after a cursor, polled every half second until the condition holds or the seconds are up, in
 * the order served. The session's stream is the only one read; the instance cursor stays at 0.
 */
export async function sessionEvents(request: APIRequestContext, after: number, until: (events: LiveEvent[]) => boolean, seconds = 20): Promise<LiveEvent[]> {
  const collected: LiveEvent[] = [];
  let cursor = after;
  const deadline = Date.now() + seconds * 1000;
  for (;;) {
    const response = await request.get(`${EVENTS}?after=${cursor}&afterInstance=0`);
    expect(response.status(), await response.text()).toBe(200);
    const poll = (await response.json()) as { events: LiveEvent[] };
    for (const event of poll.events.filter((one) => one.stream === 'session')) {
      collected.push(event);
      cursor = Math.max(cursor, event.seq);
    }
    if (until(collected) || Date.now() > deadline) return collected;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
}

/** The page's polls, with their query. */
const POLLS = /\/ocutalon\/api\/v1\/events\?/;

/**
 * How long a hold may last (ms of the host's clock) before it is reported. The page's clock stands still during a hold (holdPoll), so
 * a longer one does not show Reconnecting; it is reported in the test's annotations because it says how slow the host is.
 */
export const HOLD_LIMIT_MS = 8000;

/**
 * Holds the next /events request of the page: it resolves once a poll is out and held, and the poll reaches the server only when the
 * returned release() continues it and takes the route away (in that order: removing the route first would release the poll by itself).
 * Whatever the case seeds or publishes meanwhile is therefore in the answer of that one poll, which the page applies as one update.
 * release() resolves to how long the poll was held (ms of the host's clock, for a case that wants to report it).
 *
 * The page's own clock stands still while the poll is held, so that the time a slow host takes to seed (a docker exec, a production
 * that sends a card) cannot make the page count a silence: Reconnecting shows 10 s after the page's last answer, and a hold that long
 * would show it and change what a case counts. That needs Playwright's clock in the page from the start (page.clock.install() before
 * the page loads; holdPoll throws when it is missing): the clock is stopped a second ahead once the poll is held (freeze), and runs
 * on with the host's clock again at release().
 */
export async function holdPoll(page: Page): Promise<() => Promise<number>> {
  const faked = await page.evaluate(() => (globalThis.Date as unknown as { isFake?: boolean }).isFake === true);
  if (!faked) {
    throw new Error("holdPoll needs the page's clock: call page.clock.install() before the page loads");
  }
  let held: Route | undefined;
  let heldAt = 0;
  const handler = async (route: Route): Promise<void> => {
    if (held !== undefined) {
      await route.continue();
      return;
    }
    held = route;
    heldAt = Date.now();
  };
  await page.route(POLLS, handler);
  await expect.poll(() => held !== undefined, { message: 'a poll is out and held', timeout: 15_000 }).toBe(true);
  await freeze(page);
  return async () => {
    const ms = Date.now() - heldAt;
    await held!.continue();
    await page.unroute(POLLS, handler);
    await page.clock.resume();
    if (ms >= HOLD_LIMIT_MS) {
      test.info().annotations.push({ type: 'slow hold', description: `a poll was held for ${ms} ms of the host's clock; the page's clock stood still` });
    }
    return ms;
  };
}

/** Holds every /state request of the page until release() is called, then lets the held ones through to the server. */
export async function holdState(page: Page): Promise<{ release: () => void; held: () => number }> {
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
