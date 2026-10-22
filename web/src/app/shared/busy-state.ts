/**
 * The busy state of a button that calls the server. A framework-free state machine: it imports nothing and uses
 * only erasable TypeScript syntax, so Node runs it as it is, and its timers are injected.
 *
 * - press() starts a call, or returns false when the button is already busy, so a repeated press makes no second call.
 * - The button is busy until answered(call) is told that the call answered, or until the timeout passes.
 * - At the timeout the button is restored and the notice is raised, once. The call is not cancelled: a late answer
 *   still arrives, and answered(call) then clears the notice.
 * - Only the latest call's answer ends a busy state; the answer of an older call only clears the notice.
 * - A new press clears the notice of the call before it.
 */

/** How long a call may take before the button is restored and the notice is raised. */
export const BUSY_TIMEOUT_MS = 10_000;

/** What the button shows. */
export interface BusyView {
  /** Spinner, aria-busy and aria-disabled. */
  busy: boolean;
  /** The warning notice under the button. */
  notice: boolean;
}

export interface BusyOptions {
  setTimeout: (handler: () => void, ms: number) => unknown;
  clearTimeout: (handle: unknown) => void;
  /** Called after every change of the view. */
  onChange?: (view: BusyView) => void;
  /** Called once each time the notice is raised. */
  onNotice?: () => void;
  timeoutMs?: number;
}

export class BusyState {
  private readonly options: BusyOptions;
  private isBusy = false;
  private hasNotice = false;
  private latest = 0;
  private timer: unknown = undefined;

  constructor(options: BusyOptions) {
    this.options = options;
  }

  /** What the button shows now. */
  get view(): BusyView {
    return { busy: this.isBusy, notice: this.hasNotice };
  }

  /** The number of the latest call that press() accepted; answered() takes it. */
  get call(): number {
    return this.latest;
  }

  /** Starts a call and returns true, or returns false (and starts nothing) when the button is already busy. */
  press(): boolean {
    if (this.isBusy) {
      return false;
    }
    this.latest += 1;
    this.isBusy = true;
    this.hasNotice = false;
    const call = this.latest;
    this.timer = this.options.setTimeout(() => this.timeout(call), this.options.timeoutMs ?? BUSY_TIMEOUT_MS);
    this.changed();
    return true;
  }

  /** The call answered, early or late. */
  answered(call: number): void {
    const wasBusy = this.isBusy && call === this.latest;
    if (wasBusy) {
      this.cancelTimer();
      this.isBusy = false;
    }
    if (wasBusy || this.hasNotice) {
      this.hasNotice = false;
      this.changed();
    }
  }

  /** Drops the pending timer; the page is done with the button. */
  dispose(): void {
    this.cancelTimer();
  }

  private timeout(call: number): void {
    this.timer = undefined;
    if (!this.isBusy || call !== this.latest) {
      return;
    }
    this.isBusy = false;
    this.hasNotice = true;
    this.changed();
    this.options.onNotice?.();
  }

  private cancelTimer(): void {
    if (this.timer !== undefined) {
      this.options.clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  private changed(): void {
    this.options.onChange?.(this.view);
  }
}
