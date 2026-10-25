import type { Page } from '@playwright/test';

/**
 * Readings and steps for the browser specs that control the page's clock (page.clock) against a real stack. The page counts its contact
 * with OcuTalon on its own monotonic clock (performance.now(), which page.clock fakes), and page.clock.install() lets that clock run on
 * with the wall clock, so a margin that is counted in seconds of the test's own steps shrinks on a slow host: every real second that a
 * test spends in assertions is a second of the page's time as well. These helpers read the page's clock and place each check at a set
 * distance from the page's last answer on it, so the time spent in assertions moves no check across a threshold.
 */

/** The two requests of the live path, whose answers the page counts. */
const LIVE_PATHS = ['/ocutalon/api/v1/events', '/ocutalon/api/v1/state'];

/** The path of the page's polls. */
const POLL_PATH = '/ocutalon/api/v1/events';

/** The longest step of the page's clock: a poll that is due is made within a step, and its answer is handled between two steps. */
const STEP_MS = 1000;

/** The most steps of one runUntil, so that a clock that does not move fails the test instead of ending it by its timeout. */
const MOST_STEPS = 600;

/** The longest real time that a step waits for the requests it made to end; a request that a test holds on purpose is waited for this long at most. */
const SETTLE_MS = 2000;

/** How far ahead of the page's running clock freeze stops it. */
const FREEZE_AHEAD_MS = 1000;

/** One request of the page to the API, with its times on the page's clock. `end` and `status` are -1 while it is out; a refused or dropped request ends with status 0. */
export interface Exchange {
  path: string;
  start: number;
  end: number;
  status: number;
}

/**
 * Before the page's scripts run: logs each request of the page to the API (fetch, which is what the page's HTTP client uses) as
 * window.traffic, with the page's clock at its start and at the moment its answer arrived or it ended without one, so a test can place
 * a check relative to the page's last answer.
 */
export async function recordTraffic(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const log: Array<{ path: string; start: number; end: number; status: number }> = [];
    (window as unknown as { traffic: typeof log }).traffic = log;
    const original = window.fetch;
    window.fetch = function (this: unknown, input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      const path = new URL(url, location.href).pathname;
      if (!path.startsWith('/ocutalon/api/v1/')) {
        return original.call(window, input, init);
      }
      const exchange = { path, start: performance.now(), end: -1, status: -1 };
      log.push(exchange);
      const promise = original.call(window, input, init);
      promise.then(
        (response) => {
          exchange.end = performance.now();
          exchange.status = response.status;
        },
        () => {
          exchange.end = performance.now();
          exchange.status = 0;
        },
      );
      return promise;
    };
  });
}

/** The requests that recordTraffic has seen, in the order they were made. */
export const traffic = (page: Page): Promise<Exchange[]> => page.evaluate(() => (window as unknown as { traffic: Exchange[] }).traffic.map((one) => ({ ...one })));

/** The page's clock now, in milliseconds. */
export const pageNow = (page: Page): Promise<number> => page.evaluate(() => performance.now());

/**
 * When the page last got an answer of its live path (a 200 or a 503 of /events or /state), on the page's clock, at the arrival of the
 * answer's headers, a few milliseconds before the page handles it. For a loaded page whose polls bring no skipped Seq, the page counts
 * its 10 s and its 30 s from this instant. It does not fit a poll that found a skipped Seq (the page counts from the snapshot that the
 * poll reloads) or a 503 before the load (which arms nothing). After a refusal has been seen, no later request has been answered.
 */
export async function lastAnswerAt(page: Page): Promise<number> {
  const answered = (await traffic(page)).filter((one) => LIVE_PATHS.includes(one.path) && (one.status === 200 || one.status === 503)).map((one) => one.end);
  if (answered.length === 0) {
    throw new Error('the page has not been answered yet');
  }
  return Math.max(...answered);
}

/** The page's clock at the start of each poll it has made, in order. */
export async function pollStarts(page: Page): Promise<number[]> {
  return (await traffic(page)).filter((one) => one.path === POLL_PATH).map((one) => one.start);
}

/** The gaps between consecutive numbers. */
export const gaps = (times: number[]): number[] => times.slice(1).map((time, index) => time - times[index]!);

/**
 * Moves the page's clock on until it stands `ms` past `since` (a reading of that clock), a step of at most one second at a time so that the
 * page makes and handles its polls on the way, as it does in real time. After each step it waits until the requests that the page made
 * since the call began have ended: the page's clock moves a second in a few milliseconds, so without that wait a real answer that takes a
 * few milliseconds would take the page seconds, and the page's 10 s and 30 s would pass on the time that the host takes to answer. A request
 * that was already out when the call began (one that a test holds) is not waited for. Time that has passed already counts, so the check
 * after it stands at that distance from `since` whatever the earlier assertions took, unless they took the page past it: then it returns
 * at once and the check stands that much later. A check therefore keeps a margin from the next threshold for the time of the assertions
 * before it, or stops the clock first (freeze). The page must have been given recordTraffic.
 */
export async function runUntil(page: Page, since: number, ms: number): Promise<void> {
  const known = (await traffic(page)).length;
  for (let step = 0; step < MOST_STEPS; step += 1) {
    const left = since + ms - (await pageNow(page));
    if (left <= 0) return;
    await page.clock.runFor(Math.ceil(Math.min(STEP_MS, left)));
    await requestsEnded(page, known);
  }
  throw new Error(`the page's clock did not reach ${ms} ms past ${since}`);
}

/** Waits, for SETTLE_MS at most, until every request made after the first `known` ones has ended, one way or the other. */
async function requestsEnded(page: Page, known: number): Promise<void> {
  const limit = Date.now() + SETTLE_MS;
  while (Date.now() < limit) {
    if (!(await traffic(page)).slice(known).some((one) => one.end === -1)) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

/**
 * Stops the page's clock a second ahead of where it stands. pauseAt cannot move the clock back, and the clock runs on while the call
 * travels, so the second is what keeps a slow host from passing the time before it arrives. From then on only page.clock.runFor (and
 * runUntil) move it, so assertions read one instant and a slow host cannot let the page's timers run on; page.clock.resume() lets the
 * clock run with the wall clock again.
 */
export async function freeze(page: Page): Promise<void> {
  await page.clock.pauseAt(await page.evaluate((ahead) => Date.now() + ahead, FREEZE_AHEAD_MS));
}
