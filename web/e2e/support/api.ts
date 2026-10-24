import { expect, test, type APIRequestContext, type APIResponse, type Page, type Route } from '@playwright/test';

import { envelope } from '../sign-in/helpers';

/**
 * What the API specs share: the three routes a spec polls and posts to, one live event as /events serves it, and the two calls that
 * post a message the way the page does and wait for the session stream. api.spec.ts (Story 2.4), trace.spec.ts (Story 2.9) and links.spec.ts (Story 2.13) use them.
 * frame.spec.ts (Story 2.1) and links.spec.ts also answer the page's /state with a changed copy of the real answer (changeSnapshot).
 * The floor specs (Story 2.12) hold one poll so that what a case seeds reaches the page in a single update (holdPoll).
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
 * How long a case should hold a poll at most (ms). The page shows Reconnecting 10 s after its last answer, and its next poll starts a
 * second after that answer, so a poll held for 8 s or longer risks a banner that changes what a case counts. holdPoll reports a longer
 * hold in the test's annotations; the case's own assertions are what fail if the banner came.
 */
export const HOLD_LIMIT_MS = 8000;

/**
 * Holds the next /events request of the page: it resolves once a poll is out and held, and the poll reaches the server only when the
 * returned release() continues it and takes the route away (in that order: removing the route first would release the poll by itself). Whatever the case seeds or publishes meanwhile is therefore in the
 * answer of that one poll, which the page applies as one update. release() resolves to how long the poll was held (ms).
 */
export async function holdPoll(page: Page): Promise<() => Promise<number>> {
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
  return async () => {
    const ms = Date.now() - heldAt;
    await held!.continue();
    await page.unroute(POLLS, handler);
    if (ms >= HOLD_LIMIT_MS) {
      test.info().annotations.push({ type: 'slow hold', description: `a poll was held for ${ms} ms; Reconnecting shows 10 s after the page's last answer` });
    }
    return ms;
  };
}
