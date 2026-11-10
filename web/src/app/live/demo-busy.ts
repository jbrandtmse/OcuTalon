/**
 * The online demo's busy state on the signed-in page (Story 16.5; AD-13). A framework-free state machine: it imports nothing and
 * uses only erasable TypeScript syntax, so Node runs it as it is, and its timer is injected like ContactWatch's.
 *
 * - `makesDemoBusy` is the rule for an API answer: a 503 makes the page busy unless its body's `error.code` is `search_busy` (the Memory card's own).
 * - There are two causes. The API cause holds from an API answer of 503 until the next 2xx API answer. The trace cause holds from a
 *   status check that said busy until a later status check says otherwise.
 * - `busy` is true while either cause holds. A 2xx API answer does not clear the trace cause, and a status check does not clear the
 *   API cause.
 * - While the trace cause holds, the watch asks its owner to check the status again every DEMO_BUSY_RECHECK_MS (recheck). The owner
 *   reports the answer through statusChecked, or checkFailed when the check could not be read: a failed check does not say the demo
 *   is free, so the cause holds and the next check is armed.
 * - stop() ends the watch for good: the timer is cleared, both causes are dropped, and later reports do nothing.
 * - onChange(busy) is called once for each actual change of `busy`, never for a repeat.
 */

/** How far apart the quiet status checks are while the trace cause holds. */
export const DEMO_BUSY_RECHECK_MS = 10_000;

/** The status of an API answer that is the busy state (AD-25). */
export const DEMO_BUSY_STATUS = 503;

/** The error code of a memory read that has no answer in time: the Memory card shows its own message, and the page is not busy (Story 41.13, DW-1040). */
export const SEARCH_BUSY_CODE = 'search_busy';

/**
 * True when an API answer of this status, with this error body, makes the page busy: a 503 whose body `error.code` is not `search_busy`. The
 * one rule of the client for the busy state; the envelope interceptor asks it for every 503.
 */
export function makesDemoBusy(status: number, body: unknown): boolean {
  if (status !== DEMO_BUSY_STATUS) {
    return false;
  }
  const error = typeof body === 'object' && body !== null ? (body as { error?: unknown }).error : undefined;
  const code = typeof error === 'object' && error !== null ? (error as { code?: unknown }).code : undefined;
  return code !== SEARCH_BUSY_CODE;
}

/** What a DemoBusyWatch needs: its timer functions, injected so a test can run them on a fake clock, and the check it asks for. */
export interface DemoBusyOptions {
  /** Arms a timer and returns its handle (the page passes globalThis.setTimeout). */
  setTimeout: (handler: () => void, ms: number) => unknown;
  /** Clears a timer that setTimeout armed, by its handle. */
  clearTimeout: (handle: unknown) => void;
  /** Starts one quiet status check; its answer comes back through statusChecked or checkFailed. */
  recheck: () => void;
  /** Called once for each change of `busy`, with the new value. */
  onChange?: (busy: boolean) => void;
}

/** Holds the two causes of the demo's busy state, as the module doc says; DemoBusyState owns one. */
export class DemoBusyWatch {
  private readonly options: DemoBusyOptions;
  private apiCause = false;
  private traceCause = false;
  private shown = false;
  private ended = false;
  private timer: unknown = undefined;

  constructor(options: DemoBusyOptions) {
    this.options = options;
  }

  /** True while either cause holds. */
  get busy(): boolean {
    return this.apiCause || this.traceCause;
  }

  /** An API call answered with this status: 503 starts the API cause, any 2xx ends it, and every other status leaves it as it is. */
  apiAnswered(status: number): void {
    if (this.ended) {
      return;
    }
    if (status === DEMO_BUSY_STATUS) {
      this.apiCause = true;
    } else if (status >= 200 && status < 300) {
      this.apiCause = false;
    }
    this.publish();
  }

  /** A status check answered: busy starts the trace cause and arms the next check, and not busy ends the cause and cancels the timer. */
  statusChecked(busy: boolean): void {
    if (this.ended) {
      return;
    }
    this.traceCause = busy;
    if (busy) {
      this.arm();
    } else {
      this.cancel();
    }
    this.publish();
  }

  /** A quiet status check could not be read: the trace cause, if it holds, stays and the next check is armed. */
  checkFailed(): void {
    if (this.ended || !this.traceCause) {
      return;
    }
    this.arm();
  }

  /** Ends the watch for good: no timer is left, no cause holds, and later reports do nothing. */
  stop(): void {
    this.ended = true;
    this.cancel();
    this.apiCause = false;
    this.traceCause = false;
    this.publish();
  }

  private arm(): void {
    if (this.timer !== undefined) {
      return;
    }
    this.timer = this.options.setTimeout(() => {
      this.timer = undefined;
      if (!this.ended && this.traceCause) {
        this.options.recheck();
      }
    }, DEMO_BUSY_RECHECK_MS);
  }

  private cancel(): void {
    if (this.timer !== undefined) {
      this.options.clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  private publish(): void {
    const now = this.busy;
    if (now === this.shown) {
      return;
    }
    this.shown = now;
    this.options.onChange?.(now);
  }
}
