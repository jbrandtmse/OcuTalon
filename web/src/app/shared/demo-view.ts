import { Injectable, computed, inject, signal } from '@angular/core';

import { LiveState } from '../live/live-state';
import { readFlag, writeFlag } from './stored-flag';

/** The sessionStorage key of the Demo view switch: the choice is kept per browser tab. */
export const DEMO_VIEW_KEY = 'ocutalon.demoView.off';

/** The value the key holds when the switch is off. */
export const DEMO_VIEW_OFF = '1';

/** The value the key holds when the switch is on. */
export const DEMO_VIEW_ON = '0';

/**
 * The page's one demo view (Story 4.9): whether the demo parts (the guide, Break the feed, the simulated devices and the demo lines)
 * show. It is the server's demo mode (`available`) and the header's "Demo view" switch (`switchedOn`, on by default) both on. Every
 * reader of demo mode but the header's pill goes through `on` or `snapshot`; no component reads the snapshot's demoMode itself.
 * The switch is client-only: a change sends nothing to the server and changes no server state. The choice is read once, when the
 * service starts, from this tab's sessionStorage ('1' off, anything else on) and written on each change; a storage that throws
 * keeps the choice in memory for the page.
 */
@Injectable({ providedIn: 'root' })
export class DemoView {
  private readonly live = inject(LiveState);
  private readonly state = signal(!readFlag(() => window.sessionStorage, DEMO_VIEW_KEY, DEMO_VIEW_OFF));

  /** True while the server's snapshot says demo mode is on: the only time the switch shows. */
  readonly available = computed(() => this.live.snapshot()?.demoMode === true);

  /** The switch's state. */
  readonly switchedOn = this.state.asReadonly();

  /** True while the demo parts show: the install is a demo and the switch is on. */
  readonly on = computed(() => this.available() && this.switchedOn());

  /** The live snapshot while the demo view is on, else undefined: what the guide, phone and mailbox view models are given. */
  readonly snapshot = computed(() => (this.on() ? this.live.snapshot() : undefined));

  /** Sets the switch and keeps the choice for this tab. */
  set(on: boolean): void {
    this.state.set(on);
    writeFlag(() => window.sessionStorage, DEMO_VIEW_KEY, on ? DEMO_VIEW_ON : DEMO_VIEW_OFF);
  }
}
