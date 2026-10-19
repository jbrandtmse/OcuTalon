import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { ApiClient } from './api/api-client';
import type { StateSnapshot } from './api/api-types';
import { Header } from './header/header';

/**
 * The page: the app header over an empty main region with its one visually hidden heading. The page loads the
 * snapshot once; main's data-snapshot says how that went (loading, loaded or failed).
 */
@Component({
  selector: 'app-root',
  imports: [Header],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-header />
    <main class="main" [attr.data-snapshot]="snapshotState()">
      <h1 class="visually-hidden">OcuTalon</h1>
    </main>
  `,
  styles: `
    :host {
      display: flex;
      flex-direction: column;
      min-height: 100vh;
    }
    .main {
      flex: 1;
      background: var(--bg);
    }
  `,
})
export class App {
  private readonly api = inject(ApiClient);

  /** The snapshot, once it has loaded. */
  readonly snapshot = signal<StateSnapshot | undefined>(undefined);
  protected readonly snapshotState = signal<'loading' | 'loaded' | 'failed'>('loading');

  constructor() {
    this.api
      .state()
      .pipe(takeUntilDestroyed())
      .subscribe({
        next: (snapshot) => {
          this.snapshot.set(snapshot);
          this.snapshotState.set('loaded');
        },
        error: () => this.snapshotState.set('failed'),
      });
  }
}
