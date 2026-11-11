import { LiveAnnouncer } from '@angular/cdk/a11y';
import { DestroyRef, Injectable, inject } from '@angular/core';

import { AnnounceQueue } from './announce-queue';

/**
 * The page's one live region, polite: whatever the page announces to a screen reader goes through here, and only here (UX-DR132).
 * announce() hands the message to an AnnounceQueue, which speaks through the CDK's LiveAnnouncer and so through its one
 * `aria-live="polite"` element, setting the text as text and never as HTML (AD-13).
 * - The messages of one update (pushed in one turn of the event loop) are spoken as one text, in the order announced.
 * - Texts are spoken at least 1 s apart, because the region holds one text and each new text replaces the one before it.
 * - No more than three announcements are spoken in any 2 s: beyond that, two or more waiting messages are spoken as
 *   "{n} new updates", and a single one waits until the window has passed.
 * - Each message is spoken once: nothing is spoken twice and nothing is dropped, except a message that retract() withdraws.
 */
@Injectable({ providedIn: 'root' })
export class Announcer {
  private readonly live = inject(LiveAnnouncer);
  /** The text last handed to the live region, which holds it from 100 ms after the hand-over until the next text replaces it. */
  private lastSpoken = '';
  private readonly queue = new AnnounceQueue({
    setTimeout: (handler, ms) => globalThis.setTimeout(handler, ms),
    clearTimeout: (handle) => globalThis.clearTimeout(handle as number),
    now: () => performance.now(),
    speak: (text) => {
      this.lastSpoken = text;
      void this.live.announce(text, 'polite');
    },
  });

  constructor() {
    inject(DestroyRef).onDestroy(() => this.queue.dispose());
  }

  /** Announces the message once, without interrupting what is being read. */
  announce(message: string): void {
    this.queue.push(message);
  }

  /**
   * Withdraws a message that a later answer has made untrue: it no longer waits in the queue, and when it was the last text spoken (alone, not joined with
   * others) the live region is emptied, also when the region has not received it yet.
   */
  retract(message: string): void {
    const text = message.trim();
    this.queue.retract(text);
    if (text !== '' && this.lastSpoken === text) {
      this.lastSpoken = '';
      void this.live.announce('', 'polite');
    }
  }
}
