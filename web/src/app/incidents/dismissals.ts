import { Injectable, signal } from '@angular/core';

/**
 * The incidents that this page closed with a Dismiss (Story 6.4): a one-signal store. The 200 of the dismiss route is the owner's
 * synchronous confirmation (AD-15), so the page shows that incident as closed at once, before the owner's `incident` event arrives
 * and agrees. It reads nothing of the server: the live store stays the server's.
 * It also counts the presses of Dismiss whose reply has not come yet, by Ref (a plain count, not a signal: nothing is drawn from
 * it). The owner publishes the closed view before it answers, so that event can reach the page before the 200 does; owns() answers
 * true from the press on, so that the page never speaks a closing that its own Dismiss made, in either order.
 */
@Injectable({ providedIn: 'root' })
export class Dismissals {
  private readonly closed = signal<ReadonlySet<string>>(new Set<string>());
  private readonly waiting = new Map<string, number>();

  /** The Refs of the incidents that this page closed with a 200. */
  readonly refs = this.closed.asReadonly();

  /** Records that the dismissal of the incident answered 200. */
  add(ref: string): void {
    if (ref !== '' && !this.closed().has(ref)) {
      this.closed.update((refs) => new Set([...refs, ref]));
    }
  }

  /** Records a press of Dismiss on the incident, whose reply has not come yet. */
  pressed(ref: string): void {
    this.waiting.set(ref, (this.waiting.get(ref) ?? 0) + 1);
  }

  /** Records that the reply of one press on the incident came (a 200, an error or none). */
  settled(ref: string): void {
    const left = (this.waiting.get(ref) ?? 0) - 1;
    if (left > 0) {
      this.waiting.set(ref, left);
    } else {
      this.waiting.delete(ref);
    }
  }

  /** True for an incident that this page closed with a 200, or whose Dismiss is waiting for its reply: its closing is the page's own. */
  owns(ref: string): boolean {
    return this.closed().has(ref) || this.waiting.has(ref);
  }
}
