import { Injectable, signal } from '@angular/core';

/**
 * The incidents that this page closed with a Dismiss (Story 6.4): a one-signal store. The 200 of the dismiss route is the owner's
 * synchronous confirmation (AD-15), so the page shows that incident as closed at once, before the owner's `incident` event arrives
 * and agrees. It reads nothing of the server: the live store stays the server's.
 */
@Injectable({ providedIn: 'root' })
export class Dismissals {
  private readonly closed = signal<ReadonlySet<string>>(new Set<string>());

  /** The Refs of the incidents that this page closed with a 200. */
  readonly refs = this.closed.asReadonly();

  /** Records that the dismissal of the incident answered 200. */
  add(ref: string): void {
    if (ref !== '' && !this.closed().has(ref)) {
      this.closed.update((refs) => new Set([...refs, ref]));
    }
  }
}
