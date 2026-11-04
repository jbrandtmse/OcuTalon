/**
 * The page's view of the demo's reset (Story 16.8; AD-12, AD-13, AD-25). A framework-free module: it imports only a type and uses only
 * erasable TypeScript syntax, so Node runs it as it is, and its clock, timers and fetch are injected.
 *
 * - offerReset: the pending reset. It starts from the snapshot's nextReset; every later snapshot and every reset event offers a
 *   value. An earlier value always replaces it, a later one only while the page's clock is more than RESET_SOON_MS before it, and an
 *   empty one never does, so nothing extends a reset once its warning period has begun.
 * - isDue: the page's clock has reached the pending reset.
 * - pillView and pillDelayMs: the countdown pill of the header: its texts, whether it is urgent, and when it next changes.
 * - ResetPoller: the resetting view's quiet wait: it asks the public status at once and every RESET_POLL_MS, with no credentials, and
 *   navigates once, to the splash, when the demo is ready after the reset.
 */
import type { PublicStatus } from '../api/api-types';

/** The warning period before a reset, in milliseconds: the pending reset does not move later inside it. */
export const RESET_SOON_MS = 300_000;

/** The reset's window, in milliseconds: at most 15 minutes from the scheduled time (AD-25). */
export const RESET_WINDOW_MS = 900_000;

/** How often the resetting view asks the public status. */
export const RESET_POLL_MS = 10_000;

/** How long one status request may stay unanswered. */
export const STATUS_LIMIT_MS = 3000;

/** From this much time left the pill is urgent (UX-DR124). */
export const URGENT_MS = 600_000;

const MINUTE_MS = 60_000;

/** The address of the public status, which needs no session. */
export const STATUS_ADDRESS = '/ocutalon/public/status';

/** The texts of the pill and of the resetting view (EXPERIENCE: Pages, The resetting view; AC of Story 16.8). */
export const RESET_TEXTS = {
  /** The pill: {time} is a page time and {countdown} the countdown without its leading "in ". */
  countdown: 'Next reset {time} \u00b7 in {countdown}',
  heading: 'The demo is resetting.',
  body: 'It usually takes a few minutes. This page returns to the sign-in screen by itself.',
  title: 'Resetting \u00b7 OcuTalon',
} as const;

const fill = (template: string, values: Readonly<Record<string, string>>): string =>
  template.replace(/\{(\w+)\}/g, (_match, name: string) => values[name] ?? '');

/**
 * The pending reset after an offer: the offered value replaces the pending one when it is a readable time and the pending one is
 * empty or unreadable, or the offer is earlier, or it is later while nowMs is more than RESET_SOON_MS before the pending reset.
 * Otherwise the pending reset stays. Times are UTC ISO 8601.
 */
export function offerReset(pending: string, offered: string, nowMs: number): string {
  const next = Date.parse(offered);
  if (offered === '' || Number.isNaN(next)) {
    return pending;
  }
  const current = Date.parse(pending);
  if (pending === '' || Number.isNaN(current) || next < current) {
    return offered;
  }
  return next > current && current - nowMs > RESET_SOON_MS ? offered : pending;
}

/** True when the page's clock has reached the pending reset. No pending reset is never due. */
export function isDue(pending: string, nowMs: number): boolean {
  const due = Date.parse(pending);
  return pending !== '' && !Number.isNaN(due) && nowMs >= due;
}

/** What the pill needs from the page's time module: the page time, and the countdown in short and spoken form. */
export interface PillFormat {
  /** The hour and minute of an ISO time in the page's zone. */
  time: (iso: string) => string;
  /** The countdown from nowMs to an ISO time: "in 9 min" and its words. */
  countdown: (dueIso: string, nowMs: number) => { text: string; spoken: string };
  /** The countdown in words of whole minutes: "in 1 hour 42 minutes", and "in 1 minute" through the last minute. */
  spoken: (dueIso: string, nowMs: number) => string;
}

/** The pill as it shows: the text (hidden from assistive technology), the same in words, and whether it is urgent. */
export interface Pill {
  text: string;
  spoken: string;
  urgent: boolean;
}

const withoutIn = (countdown: string): string => countdown.replace(/^in /, '');

/**
 * The header's countdown pill, or undefined when there is nothing to show: only on the online demo, and only with a pending reset.
 * It reads "Next reset 16:00 \u00b7 in 1 h 42 min", urgent from URGENT_MS before the reset.
 */
export function pillView(onlineDemo: boolean, pending: string, nowMs: number, format: PillFormat): Pill | undefined {
  const due = Date.parse(pending);
  if (!onlineDemo || pending === '' || Number.isNaN(due)) {
    return undefined;
  }
  const time = format.time(pending);
  return {
    text: fill(RESET_TEXTS.countdown, { time, countdown: withoutIn(format.countdown(pending, nowMs).text) }),
    spoken: fill(RESET_TEXTS.countdown, { time, countdown: withoutIn(format.spoken(pending, nowMs)) }),
    urgent: due - nowMs <= URGENT_MS,
  };
}

/**
 * How long until the pill next changes, in milliseconds, or undefined when there is nothing to wait for: at the next whole
 * minute of the time left, every second inside the last minute, and when the time left reaches URGENT_MS. The delay is never
 * below 1.
 */
export function pillDelayMs(pending: string, nowMs: number): number | undefined {
  const left = Date.parse(pending) - nowMs;
  if (pending === '' || Number.isNaN(left) || left <= 0) {
    return undefined;
  }
  let boundary: number;
  if (left <= MINUTE_MS) {
    boundary = (Math.ceil(left / 1000) - 1) * 1000;
  } else {
    boundary = (Math.ceil((left + 1000) / MINUTE_MS) - 1) * MINUTE_MS - 1000;
    if (left > URGENT_MS && boundary < URGENT_MS) {
      boundary = URGENT_MS;
    }
  }
  return Math.max(left - boundary, 1);
}

/** What the poller reads from the public status. */
export type StatusAnswer = Pick<PublicStatus, 'ready' | 'lastReset'>;

/** The status JSON as an answer, or undefined for anything else (the maintenance page's HTML, an error, a body of another shape). */
export function parseStatus(body: unknown): StatusAnswer | undefined {
  if (typeof body !== 'object' || body === null) {
    return undefined;
  }
  const { ready, lastReset } = body as { ready?: unknown; lastReset?: unknown };
  if (typeof ready !== 'boolean' || (lastReset !== null && lastReset !== undefined && typeof lastReset !== 'string')) {
    return undefined;
  }
  return { ready, lastReset: lastReset ?? null };
}

/**
 * True when the demo is ready after the reset: the status is ready and its lastReset is strictly later than the time the page loaded
 * (so the splash it lands on shows the reset notice), or the page's clock is at least RESET_WINDOW_MS past the pending reset (a
 * reset that failed or ran late never strands the page).
 */
export function shouldNavigate(answer: StatusAnswer | undefined, loadedAt: string, pending: string, nowMs: number): boolean {
  if (answer === undefined || !answer.ready) {
    return false;
  }
  const last = Date.parse(answer.lastReset ?? '');
  const loaded = Date.parse(loadedAt);
  if (!Number.isNaN(last) && !Number.isNaN(loaded) && last > loaded) {
    return true;
  }
  const due = Date.parse(pending);
  return !Number.isNaN(due) && nowMs >= due + RESET_WINDOW_MS;
}

/** The part of a fetch response that the poller reads. */
export interface PollResponse {
  ok: boolean;
  json: () => Promise<unknown>;
}

/** What the poller needs: fetch, timers and the clock injected, the load time and pending reset, and where to go. */
export interface PollerOptions {
  fetch: (address: string, init: { credentials: 'omit'; cache: 'no-store'; signal: AbortSignal }) => Promise<PollResponse>;
  setTimeout: (handler: () => void, ms: number) => unknown;
  clearTimeout: (handle: unknown) => void;
  /** The page's clock in milliseconds since the epoch. */
  now: () => number;
  /** The time the page loaded, UTC ISO 8601 to the second. */
  loadedAt: string;
  /** The pending reset when the view was entered. */
  pending: string;
  /** The address of the splash with the load time. */
  target: string;
  /** Goes to the address, replacing the page (location.replace). */
  navigate: (address: string) => void;
}

/**
 * The resetting view's wait. start() asks the public status at once, then every RESET_POLL_MS: a GET with no credentials, no cache
 * and a STATUS_LIMIT_MS limit. A failed request, a timeout or an answer that is not the status JSON counts as not ready, silently.
 * When shouldNavigate holds, it navigates once and stops; stop() ends it for good.
 */
export class ResetPoller {
  private readonly options: PollerOptions;
  private started = false;
  private ended = false;
  private asked = 0;
  private timer: unknown = undefined;

  constructor(options: PollerOptions) {
    this.options = options;
  }

  /** Begins asking. Does nothing after the first call. */
  start(): void {
    if (!this.started) {
      this.started = true;
      this.poll();
    }
  }

  /** Ends the wait: no timer is left and no later answer navigates. */
  stop(): void {
    this.ended = true;
    if (this.timer !== undefined) {
      this.options.clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  private poll(): void {
    if (this.ended) {
      return;
    }
    this.timer = this.options.setTimeout(() => this.poll(), RESET_POLL_MS);
    void this.ask();
  }

  private async ask(): Promise<void> {
    const controller = new AbortController();
    let limit: unknown;
    const expired = new Promise<undefined>((resolve) => {
      limit = this.options.setTimeout(() => {
        controller.abort();
        resolve(undefined);
      }, STATUS_LIMIT_MS);
    });
    const answer = await Promise.race([this.read(controller.signal), expired]);
    this.options.clearTimeout(limit);
    if (this.ended || !shouldNavigate(answer, this.options.loadedAt, this.options.pending, this.options.now())) {
      return;
    }
    this.stop();
    this.options.navigate(this.options.target);
  }

  private async read(signal: AbortSignal): Promise<StatusAnswer | undefined> {
    this.asked += 1;
    try {
      const response = await this.options.fetch(`${STATUS_ADDRESS}?t=${this.asked}`, { credentials: 'omit', cache: 'no-store', signal });
      return response.ok ? parseStatus(await response.json()) : undefined;
    } catch {
      return undefined;
    }
  }
}
