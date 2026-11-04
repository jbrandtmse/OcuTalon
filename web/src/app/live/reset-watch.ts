import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';

import { PAGE_LOADED_AT, PAGE_LOADED_AT_MS, splashAddress } from '../session/splash-address';
import { LiveState } from './live-state';
import { ResetPoller, isDue, offerReset } from './reset-schedule';

/** The longest delay a browser timer holds (a 32-bit number of milliseconds); a longer wait is armed again when it ends. */
const LONGEST_TIMER_MS = 2_147_483_647;

/**
 * The page's pending reset and the switch to the resetting view (Story 16.8; AD-12, AD-25), kept in the page by one service.
 * - `pending` starts from the snapshot's nextReset, and every later snapshot and every reset event offers a value (offerReset: an
 *   earlier value replaces it, a later one only while more than 300 s remain, an empty one never). A local install's snapshot has
 *   none, so it never has a pending reset.
 * - The page enters the resetting view when its clock reaches the pending reset. It checks on a timer set to the pending reset, at
 *   every answer of the live path, at every change of the page's contact, and at every 401 (SessionGate asks enterIfDue first).
 * - Entering happens once: it ends the live path (LiveState.stop(), so no request under /ocutalon/api/ follows), sets `resetting`,
 *   which App renders as the resetting view, and starts the quiet wait for the demo (ResetPoller), which ends with one navigation to
 *   the splash carrying the time the page loaded.
 * This class announces nothing and moves no focus.
 */
@Injectable({ providedIn: 'root' })
export class ResetWatch {
  private readonly live = inject(LiveState);
  private readonly pendingState = signal('');
  private readonly resettingState = signal(false);
  private timer: ReturnType<typeof setTimeout> | undefined;
  private poller: ResetPoller | undefined;

  /** The next scheduled reset the page knows, UTC ISO 8601; empty when it knows none. */
  readonly pending = this.pendingState.asReadonly();

  /** True from the moment the page enters the resetting view. */
  readonly resetting = this.resettingState.asReadonly();

  private readonly snapshotReset = computed(() => this.live.snapshot()?.nextReset ?? '');
  private readonly eventReset = computed(() => this.live.store()?.reset?.nextReset ?? '');

  constructor() {
    effect(() => {
      const value = this.snapshotReset();
      untracked(() => this.offer(value));
    });
    effect(() => {
      const value = this.eventReset();
      untracked(() => this.offer(value));
    });
    effect(() => {
      this.live.contact();
      this.live.answers();
      untracked(() => this.check());
    });
    effect((onCleanup) => {
      this.pending();
      untracked(() => this.arm());
      onCleanup(() => this.disarm());
    });
  }

  /**
   * True when the page's clock is at or past the pending reset, or the page is already resetting: the page is in the resetting view
   * (entering it now if it was not). A 401 at that time belongs to the reset and not to the sign-out path.
   */
  enterIfDue(): boolean {
    if (this.resettingState()) {
      return true;
    }
    if (isDue(this.pendingState(), Date.now())) {
      this.enter();
      return true;
    }
    return false;
  }

  private offer(value: string): void {
    this.pendingState.update((pending) => offerReset(pending, value, Date.now()));
  }

  private check(): void {
    if (!this.resettingState() && isDue(this.pendingState(), Date.now())) {
      this.enter();
    }
  }

  /** Sets the timer to the pending reset. */
  private arm(): void {
    this.disarm();
    const pending = this.pendingState();
    if (this.resettingState() || pending === '' || Number.isNaN(Date.parse(pending))) {
      return;
    }
    const wait = Math.min(Math.max(Date.parse(pending) - Date.now(), 0), LONGEST_TIMER_MS);
    this.timer = globalThis.setTimeout(() => {
      this.timer = undefined;
      this.check();
      this.arm();
    }, wait);
  }

  private disarm(): void {
    if (this.timer !== undefined) {
      globalThis.clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  private enter(): void {
    if (this.resettingState()) {
      return;
    }
    this.resettingState.set(true);
    this.disarm();
    this.live.stop();
    this.poller = new ResetPoller({
      fetch: (address, init) => globalThis.fetch(address, init),
      setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
      clearTimeout: (handle) => globalThis.clearTimeout(handle as ReturnType<typeof setTimeout>),
      now: () => Date.now(),
      loadedAt: PAGE_LOADED_AT,
      pending: this.pendingState(),
      target: splashAddress(PAGE_LOADED_AT_MS),
      navigate: (address) => globalThis.location.replace(address),
    });
    this.poller.start();
  }
}
