import { DestroyRef, Injectable, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { ApiClient } from '../api/api-client';
import type { StateSnapshot } from '../api/api-types';

/** How the snapshot's load went. */
export type SnapshotStatus = 'loading' | 'loaded' | 'failed';

/**
 * The page's one live-state service: it loads the snapshot once per page load, and every consumer reads it from
 * here. The live events join it with the polling.
 */
@Injectable({ providedIn: 'root' })
export class LiveState {
  private readonly api = inject(ApiClient);
  private readonly destroyRef = inject(DestroyRef);
  private requested = false;

  /** The snapshot, once it has loaded. */
  readonly snapshot = signal<StateSnapshot | undefined>(undefined);

  /** Loading until the snapshot answers, then loaded or failed. */
  readonly status = signal<SnapshotStatus>('loading');

  /** Asks for the snapshot; every call after the first does nothing. */
  load(): void {
    if (this.requested) {
      return;
    }
    this.requested = true;
    this.api
      .state()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (snapshot) => {
          this.snapshot.set(snapshot);
          this.status.set('loaded');
        },
        error: () => this.status.set('failed'),
      });
  }
}
