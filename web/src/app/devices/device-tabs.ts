import { Injectable, signal } from '@angular/core';

import { readFlag, writeFlag } from '../shared/stored-flag';
import { type DeviceTab, MAILBOX_FLAG, TAB_KEY } from './device-view';

/** The value stored for the phone. */
const PHONE_FLAG = 'phone';

/**
 * The selected tab of the simulated device panel (Story 4.5), remembered per browser in localStorage under `ocutalon.devices.tab`: the
 * mailbox when the key holds `mailbox`, and the phone for anything else. A storage that cannot be read or written leaves the choice to
 * this page's life. Only the user's own action selects (an arrow key, a click, a guide's Show me); content never does.
 */
@Injectable({ providedIn: 'root' })
export class DeviceTabs {
  private readonly state = signal<DeviceTab>(readFlag(() => localStorage, TAB_KEY, MAILBOX_FLAG) ? 'mailbox' : 'phone');

  /** The selected tab. */
  readonly selected = this.state.asReadonly();

  /** Selects the tab and remembers it. */
  select(tab: DeviceTab): void {
    this.state.set(tab);
    writeFlag(() => localStorage, TAB_KEY, tab === 'mailbox' ? MAILBOX_FLAG : PHONE_FLAG);
  }
}
