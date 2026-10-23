import { Injectable, computed, inject, signal } from '@angular/core';

import { LiveState } from '../live/live-state';
import { needsSignInHelp, TRACE_DONT_SHOW_KEY, TRACE_FLAG, TRACE_SEEN_KEY } from './trace-view';

/** Whether the storage holds the flag; false when it does not or cannot be read. */
function readFlag(open: () => Storage, key: string): boolean {
  try {
    return open().getItem(key) === TRACE_FLAG;
  } catch {
    return false;
  }
}

/** Stores the flag; a storage that fails leaves the flag to the page's own memory. */
function writeFlag(open: () => Storage, key: string): void {
  try {
    open().setItem(key, TRACE_FLAG);
  } catch {
    /* The flag holds for this page only. */
  }
}

/**
 * The state of the Visual Trace sign-in help (UX-DR38, UX-DR128, UX-DR140, FR-14): the one source for the trace links and
 * the Visual Trace menu. The help is needed on a local or IPM install (the snapshot says onlineDemo is false) until it has
 * been shown in this tab's session (sessionStorage) or "Don't show this again" was pressed (localStorage, per browser).
 * Both flags are read once, when the service starts, and held in memory afterwards, so a storage that throws still gives
 * a help that shows once per page load.
 */
@Injectable({ providedIn: 'root' })
export class TraceHelp {
  private readonly live = inject(LiveState);
  private readonly seen = signal(readFlag(() => window.sessionStorage, TRACE_SEEN_KEY));
  private readonly dontShow = signal(readFlag(() => window.localStorage, TRACE_DONT_SHOW_KEY));

  /** True while the help is still to be shown before a trace opens. */
  readonly needed = computed(() => needsSignInHelp(this.live.snapshot()?.onlineDemo, this.seen(), this.dontShow()));

  /** Records that the help was shown in this tab's session. */
  markSeen(): void {
    this.seen.set(true);
    writeFlag(() => window.sessionStorage, TRACE_SEEN_KEY);
  }

  /** Records "Don't show this again" for this browser. */
  dontShowAgain(): void {
    this.dontShow.set(true);
    writeFlag(() => window.localStorage, TRACE_DONT_SHOW_KEY);
  }
}
