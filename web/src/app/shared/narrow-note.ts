import { Injectable, inject, signal } from '@angular/core';

import { Announcer } from './announcer';
import { LAYOUT_TEXTS, NOTE_CLOSED_KEY, NOTE_FLAG, NOTE_SHOWN_KEY } from './layout-view';
import { readFlag, writeFlag } from './stored-flag';

/**
 * The narrow-window note (UX-DR35, UX-DR128, UX-DR138): "This page is designed for a wider window. Everything still works." It shows
 * once per browser session, in the stacked layout, until it is closed, which is remembered for the browser. The "shown" flag is in
 * sessionStorage and the "closed" flag in localStorage. Both are read once, when the service starts, and held in memory afterwards,
 * so a storage that throws still gives a note that shows once per page load and a Close that holds for the page.
 *
 * A note that appears at load is silent. One that appears after load, because the window narrowed, is announced once through the
 * Announcer. Leaving the stacked layout hides the note, and it does not come back in that browser session.
 */
@Injectable({ providedIn: 'root' })
export class NarrowNote {
  private readonly announcer = inject(Announcer);
  private shown = readFlag(() => window.sessionStorage, NOTE_SHOWN_KEY, NOTE_FLAG);
  private closed = readFlag(() => window.localStorage, NOTE_CLOSED_KEY, NOTE_FLAG);
  private readonly visibleState = signal(false);

  /** True while the note shows. */
  readonly visible = this.visibleState.asReadonly();

  /** The layout is stacked or not; atLoad says that this is the page's first look at it. */
  layoutChanged(stacked: boolean, atLoad: boolean): void {
    if (!stacked) {
      this.visibleState.set(false);
      return;
    }
    if (this.shown || this.closed) {
      return;
    }
    this.shown = true;
    writeFlag(() => window.sessionStorage, NOTE_SHOWN_KEY, NOTE_FLAG);
    this.visibleState.set(true);
    if (!atLoad) {
      this.announcer.announce(LAYOUT_TEXTS.note);
    }
  }

  /** Hides the note and records that it was closed in this browser. */
  close(): void {
    this.closed = true;
    this.visibleState.set(false);
    writeFlag(() => window.localStorage, NOTE_CLOSED_KEY, NOTE_FLAG);
  }
}
