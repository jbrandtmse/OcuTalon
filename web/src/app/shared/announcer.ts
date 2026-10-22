import { LiveAnnouncer } from '@angular/cdk/a11y';
import { Injectable, inject } from '@angular/core';

/** The page's one live region, polite: whatever the page announces to a screen reader goes through here. */
@Injectable({ providedIn: 'root' })
export class Announcer {
  private readonly live = inject(LiveAnnouncer);

  /** Announces the message once, without interrupting what is being read. */
  announce(message: string): void {
    void this.live.announce(message, 'polite');
  }
}
