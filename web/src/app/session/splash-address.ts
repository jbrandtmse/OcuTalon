/**
 * The splash's address as the page returns to it (AD-13, Story 16.8), and the time the page loaded. The load time is captured once,
 * when the page's script starts, and is what the splash compares with the last reset it knows: a reset later than the load time
 * cleared this page's session, so the splash says so. A framework-free module: it imports nothing, so Node runs it as it is.
 * Story 16.4 returns to the same address after the idle cap and for a 401, and adds ended=1 after a changed epoch: the splash then shows
 * no place-freed notice, because the visitor was not away (SessionGate).
 */

/** The application's own page, which shows the splash without a session. */
const HOME = '/ocutalon/';

/** The instant the page's script started, in milliseconds since the epoch. */
export const PAGE_LOADED_AT_MS: number = Date.now();

/** An instant as UTC ISO 8601 to the second, such as 2026-10-25T07:49:30Z (the form of every time the server stores). */
export function utcSeconds(ms: number): string {
  return `${new Date(ms).toISOString().slice(0, 19)}Z`;
}

/** The page's load time as UTC ISO 8601 to the second. */
export const PAGE_LOADED_AT: string = utcSeconds(PAGE_LOADED_AT_MS);

/**
 * The splash's address with the time the page loaded: /ocutalon/?since=<UTC ISO 8601 to the second>, and with ended set (an epoch
 * change: another session began in this browser) also &ended=1.
 */
export function splashAddress(loadedAtMs: number, ended = false): string {
  return `${HOME}?since=${utcSeconds(loadedAtMs)}${ended ? '&ended=1' : ''}`;
}
