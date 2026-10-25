/**
 * The page's contact with OcuTalon (Story 2.11; AD-12). A framework-free state machine: it imports nothing and uses only
 * erasable TypeScript syntax, so Node runs it as it is, and its timers are injected.
 *
 * - The state is `ok` until answered() has been called, and no timer is armed before that.
 * - answered() says that a live path answered (in release 1, the polling). The state is `ok` from then on, and both thresholds
 *   count again from that call: `reconnecting` after RECONNECTING_AFTER_MS with no further answer, `unreachable` after
 *   UNREACHABLE_AFTER_MS.
 * - stop() ends the watch for good: the timers are cleared, the state is `ok`, and a later answered() does nothing.
 * - onChange(state) is called once for each actual change of the state, never for a repeat.
 * - pollDelay() is how long the poll waits before it asks again: the normal delay, except that an unreachable page starts one
 *   attempt each UNREACHABLE_RETRY_MS.
 */

/** Whether the live path is answering, answered a while ago, or has not answered for long. */
export type ContactState = 'ok' | 'reconnecting' | 'unreachable';

/** How long with no answer before the state is `reconnecting`. */
export const RECONNECTING_AFTER_MS = 10_000;

/** How long with no answer before the state is `unreachable`. */
export const UNREACHABLE_AFTER_MS = 30_000;

/** How far apart the polls start while the state is `unreachable`; the banner says "Retrying every 10 seconds". */
export const UNREACHABLE_RETRY_MS = 10_000;

/** The status of an API answer that is the busy state (AD-25), which is an answer of the live path and not a lost contact. */
export const BUSY_STATUS = 503;

/** What a ContactWatch needs: the timer functions it arms its two thresholds with, injected so a test can run them on a fake clock. */
export interface ContactOptions {
  /** Arms a timer and returns its handle (the page passes globalThis.setTimeout). */
  setTimeout: (handler: () => void, ms: number) => unknown;
  /** Clears a timer that setTimeout armed, by its handle. */
  clearTimeout: (handle: unknown) => void;
  /** Called once for each change of the state, with the new state. */
  onChange?: (state: ContactState) => void;
}

/** Counts the page's contact from the last answer of its live path, as the module doc says; LiveState owns one. */
export class ContactWatch {
  private readonly options: ContactOptions;
  private current: ContactState = 'ok';
  private ended = false;
  private reconnectingTimer: unknown = undefined;
  private unreachableTimer: unknown = undefined;

  constructor(options: ContactOptions) {
    this.options = options;
  }

  /** The state now. */
  get state(): ContactState {
    return this.current;
  }

  /** A live path answered: the state is `ok`, and both thresholds count from now. After stop() it does nothing. */
  answered(): void {
    if (this.ended) {
      return;
    }
    this.cancelTimers();
    this.change('ok');
    this.reconnectingTimer = this.options.setTimeout(() => {
      this.reconnectingTimer = undefined;
      this.change('reconnecting');
    }, RECONNECTING_AFTER_MS);
    this.unreachableTimer = this.options.setTimeout(() => {
      this.unreachableTimer = undefined;
      this.change('unreachable');
    }, UNREACHABLE_AFTER_MS);
  }

  /** Ends the watch for good: no timer is left, the state is `ok`, and answered() does nothing from now on. */
  stop(): void {
    this.ended = true;
    this.cancelTimers();
    this.change('ok');
  }

  private cancelTimers(): void {
    if (this.reconnectingTimer !== undefined) {
      this.options.clearTimeout(this.reconnectingTimer);
      this.reconnectingTimer = undefined;
    }
    if (this.unreachableTimer !== undefined) {
      this.options.clearTimeout(this.unreachableTimer);
      this.unreachableTimer = undefined;
    }
  }

  private change(next: ContactState): void {
    if (next === this.current) {
      return;
    }
    this.current = next;
    this.options.onChange?.(next);
  }
}

/**
 * How long the poll waits before the next one. `unreachable` gives what is left of UNREACHABLE_RETRY_MS after the poll that
 * just ended started (elapsedMs), never less than 0, so each attempt starts UNREACHABLE_RETRY_MS after the previous one
 * started; `ok` and `reconnecting` give normalMs.
 */
export function pollDelay(state: ContactState, elapsedMs: number, normalMs: number): number {
  return state === 'unreachable' ? Math.max(0, UNREACHABLE_RETRY_MS - elapsedMs) : normalMs;
}
