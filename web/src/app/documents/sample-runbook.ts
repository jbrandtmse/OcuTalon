import { DestroyRef, Injectable, computed, effect, inject, signal, untracked } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { ApiClient } from '../api/api-client';
import { LiveState } from '../live/live-state';
import type { DocumentPayload } from '../live/payloads';
import { hasDocuments } from './documents-view';

/**
 * What the demo guide knows about the sample runbook (Story 20.3; AD-12, AD-21), kept by one service that the More to try panel and the
 * Documents page read.
 * - `none()` is true only once GET /v1/documents has answered and the visitor's own list holds no document in any state: that list overlaid
 *   by the live store's `document` events (documents-view.hasDocuments). A list not yet loaded, or one whose GET failed, is unknown and reads
 *   false, so the panel keeps its link. The GET runs when the service is made and again whenever the snapshot reloads.
 * - `ask()` is the panel's one-shot request, made by the user's own press, that the Documents page press its Add the sample runbook;
 *   `take()` hands the request to the page once and clears it.
 * This class posts nothing, announces nothing and moves no focus.
 */
@Injectable({ providedIn: 'root' })
export class SampleRunbook {
  private readonly api = inject(ApiClient);
  private readonly live = inject(LiveState);
  private readonly destroyed = inject(DestroyRef);

  /** The documents as GET /v1/documents last listed them; undefined until it has answered. */
  private readonly listed = signal<readonly DocumentPayload[] | undefined>(undefined);
  private asked = false;

  /** True once the visitor's own list is known and empty. */
  readonly none = computed(() => {
    const server = this.listed();
    return server !== undefined && !hasDocuments(server, this.live.store()?.documents ?? {});
  });

  constructor() {
    effect(() => {
      this.live.snapshot();
      untracked(() => this.fetch());
    });
  }

  /** The user pressed the panel's sample control: the Documents page presses its own button once it has loaded. */
  ask(): void {
    this.asked = true;
  }

  /** True once after `ask()`: the request is the caller's now. */
  take(): boolean {
    const was = this.asked;
    this.asked = false;
    return was;
  }

  private fetch(): void {
    this.api
      .documents()
      .pipe(takeUntilDestroyed(this.destroyed))
      .subscribe({
        next: (body) => this.listed.set(body.documents ?? []),
        error: () => this.listed.set(undefined),
      });
  }
}
