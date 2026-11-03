import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';

import { ApiClient } from '../api/api-client';
import type { PublicStatus } from '../api/api-types';
import { DemoBusyWatch } from './demo-busy';

/**
 * How long a status check waits for its answer: a check that is silent for this long opens the window (the proxy's busy page covers a
 * full demo). It stays well inside the 5 s that a click's activation lasts, because a window opened after that is blocked.
 */
export const STATUS_TIMEOUT_MS = 3000;

/**
 * The online demo's busy state of the signed-in page (Story 16.5; AD-13, AD-25), kept in the page by one DemoBusyWatch.
 * - apiAnswered(status) is the envelope interceptor's report of every API answer: a 503 makes the page busy, and a later 2xx clears
 *   that cause.
 * - openTrace(url) is the online demo's trace check, run at the press of a Trace link: it asks the trace form of /ocutalon/public/status
 *   (?for=trace, whose busy comes from the connection check alone, so that a full house of visitors never refuses Visual Trace) through
 *   ApiClient.publicStatus (with a unique query, so that no cache answers) and opens the window only when the answer says the demo is not busy. A busy answer shows the
 *   banner and opens nothing, and an answer that does not come (no answer within STATUS_TIMEOUT_MS, or not JSON) opens the window.
 * - While a busy status holds the page busy, the same check (the trace form) runs again every 10 s, quietly: it takes no session and announces nothing.
 * The banner stack renders `busy`; this class announces nothing and moves no focus.
 */
@Injectable({ providedIn: 'root' })
export class DemoBusyState {
  private readonly api = inject(ApiClient);
  private readonly state = signal(false);
  private readonly watch = new DemoBusyWatch({
    setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
    clearTimeout: (handle) => globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>),
    recheck: () => void this.recheck(),
    onChange: (busy) => this.state.set(busy),
  });

  /** True while an API 503 or a busy status holds the page busy. */
  readonly busy = this.state.asReadonly();

  /** An API call answered with this status. */
  apiAnswered(status: number): void {
    this.watch.apiAnswered(status);
  }

  /** Opens a trace window at the url unless the demo is busy: the check of the module doc. */
  async openTrace(url: string): Promise<void> {
    const status = await this.check();
    if (status !== undefined) {
      this.watch.statusChecked(status.busy);
      if (status.busy) {
        return;
      }
    }
    globalThis.open(url, '_blank', 'noopener,noreferrer');
  }

  /** The quiet re-check of a busy status. */
  private async recheck(): Promise<void> {
    const status = await this.check();
    if (status === undefined) {
      this.watch.checkFailed();
    } else {
      this.watch.statusChecked(status.busy);
    }
  }

  /** The public status, or undefined when no answer comes within STATUS_TIMEOUT_MS or the answer is not the status. */
  private async check(): Promise<PublicStatus | undefined> {
    try {
      const status = await firstValueFrom(
        this.api.publicStatus().pipe(timeout(STATUS_TIMEOUT_MS)),
      );
      return typeof status === 'object' && status !== null && typeof status.busy === 'boolean' ? status : undefined;
    } catch {
      return undefined;
    }
  }
}
