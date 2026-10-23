import { expect, type APIRequestContext, type APIResponse } from '@playwright/test';

import { envelope } from '../sign-in/helpers';

/**
 * What the API specs share: the three routes a spec polls and posts to, one live event as /events serves it, and the two calls that
 * post a message the way the page does and wait for the session stream. api.spec.ts (Story 2.4) and trace.spec.ts (Story 2.9) use them.
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
