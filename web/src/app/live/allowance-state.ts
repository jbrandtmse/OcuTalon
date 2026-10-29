import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';

import { LiveState } from './live-state';
import { allowanceOf, nextChange, type Refusal } from './allowance-view';

/** The longest delay a browser timer holds (a 32-bit number of milliseconds); a longer wait is armed again when it ends. */
const LONGEST_TIMER_MS = 2_147_483_647;

/**
 * The session's message allowance on the page (Story 16.9; AD-12, AD-20), kept by one service that the banner stack, the composer and
 * the demo guide read.
 * - The window comes from two places (live/allowance-view.ts): the store's `allowance` status condition, which /state computes and
 *   StatusMonitor publishes, and the last 429 refusal that a post of this page got (`refused`). `active()` is the window that holds
 *   now, or undefined.
 * - A clock signal, which a timer sets to the page's time at the next change (the time of the window that holds, as reset-watch.ts
 *   arms its timer to the pending reset), makes `active()` clear at the time on the page's own clock, whether or not an event brings
 *   the clear. The timer is armed again after it fires, until no time is ahead. A new condition or refusal sets the clock too, so a
 *   window whose time has already passed on the page never shows.
 * This class announces nothing and moves no focus.
 */
@Injectable({ providedIn: 'root' })
export class AllowanceState {
  private readonly live = inject(LiveState);
  private readonly refusal = signal<Refusal | undefined>(undefined);
  private readonly clock = signal(Date.now());
  private timer: ReturnType<typeof setTimeout> | undefined;

  private readonly condition = computed(() => this.live.store()?.status['allowance']);

  /** The allowance window that holds now: the limit (when known) and the UTC ISO time when the session can send again; undefined when none holds. */
  readonly active = computed(() => allowanceOf(this.condition(), this.refusal(), this.clock()));

  constructor() {
    effect((onCleanup) => {
      this.condition();
      this.refusal();
      untracked(() => {
        this.clock.set(Date.now());
        this.arm();
      });
      onCleanup(() => this.disarm());
    });
  }

  /** A post of this page was refused with a 429 allowance: the window holds until the refusal's retryAt. */
  refused(refusal: Refusal): void {
    this.refusal.set(refusal);
    this.clock.set(Date.now());
  }

  /** Sets the timer to the next time the window changes, if one is ahead. */
  private arm(): void {
    this.disarm();
    const now = Date.now();
    const next = nextChange(this.condition(), this.refusal(), now);
    if (next === undefined) {
      return;
    }
    this.timer = globalThis.setTimeout(
      () => {
        this.timer = undefined;
        this.clock.set(Date.now());
        this.arm();
      },
      Math.min(Math.max(next - now, 0), LONGEST_TIMER_MS),
    );
  }

  private disarm(): void {
    if (this.timer !== undefined) {
      globalThis.clearTimeout(this.timer);
      this.timer = undefined;
    }
  }
}
