/**
 * The page's idle cap (Story 16.4; AD-13): how long the page may go with no key press, click or sent message before it frees its
 * place. A framework-free class: it imports nothing and uses only erasable TypeScript syntax, so Node runs it as it is, and its timers
 * and clock are injected.
 *
 * - start(seconds) arms the cap and counts from now. A second start replaces the first.
 * - touch() says that the user was active: the cap counts from now again. It does nothing while the cap is not running.
 * - stop() ends the cap for good until the next start: no timer is left and the handler is not called.
 * - The handler is called once, when `seconds` have passed since the latest touch. The cap is judged on the wall clock (`now`), not on
 *   the timer alone: a timer that fires late (the computer slept) calls the handler at once when the cap has passed, and one that
 *   fires early arms itself again for what is left.
 */

/** The longest delay a browser timer holds (a 32-bit number of milliseconds); a longer wait is armed again when it ends. */
const LONGEST_TIMER_MS = 2_147_483_647;

/** What an IdleCap needs: the timer functions, the wall clock and the handler, injected so that a test can run them on a fake clock. */
export interface IdleCapOptions {
  /** Arms a timer and returns its handle (the page passes globalThis.setTimeout). */
  setTimeout: (handler: () => void, ms: number) => unknown;
  /** Clears a timer that setTimeout armed, by its handle. */
  clearTimeout: (handle: unknown) => void;
  /** The wall clock in milliseconds (the page passes Date.now). */
  now: () => number;
  /** Called once when the cap has passed with no activity. */
  onIdle: () => void;
}

/** Counts the idle time of the page, as the module doc says; SessionGate owns one. */
export class IdleCap {
  private readonly options: IdleCapOptions;
  private capMs = 0;
  private lastActive = 0;
  private running = false;
  private timer: unknown = undefined;

  constructor(options: IdleCapOptions) {
    this.options = options;
  }

  /** True from start() until stop() or the call of the handler. */
  get active(): boolean {
    return this.running;
  }

  /** Arms the cap for that many seconds from now; a value that is not a number above 0 arms nothing. */
  start(seconds: number): void {
    this.stop();
    if (!Number.isFinite(seconds) || seconds <= 0) {
      return;
    }
    this.capMs = seconds * 1000;
    this.lastActive = this.options.now();
    this.running = true;
    this.arm(this.capMs);
  }

  /** The user was active: the cap counts from now. */
  touch(): void {
    if (this.running) {
      this.lastActive = this.options.now();
    }
  }

  /** Ends the cap: no timer is left and the handler is not called. */
  stop(): void {
    this.running = false;
    this.disarm();
  }

  private arm(ms: number): void {
    this.disarm();
    this.timer = this.options.setTimeout(() => {
      this.timer = undefined;
      this.expired();
    }, Math.min(Math.max(ms, 0), LONGEST_TIMER_MS));
  }

  private disarm(): void {
    if (this.timer !== undefined) {
      this.options.clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  /** The timer fired: the handler when the wall clock says the cap has passed, else the timer again for what is left. */
  private expired(): void {
    if (!this.running) {
      return;
    }
    const left = this.capMs - (this.options.now() - this.lastActive);
    if (left <= 0) {
      this.running = false;
      this.options.onIdle();
      return;
    }
    this.arm(left);
  }
}
