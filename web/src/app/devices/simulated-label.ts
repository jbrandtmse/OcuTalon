import { ChangeDetectionStrategy, Component } from '@angular/core';

import { DEVICE_TEXTS } from './device-view';

/**
 * The Simulated label (Story 4.5; EXPERIENCE, DESIGN): an amber outlined pill reading "Simulated", always visible inside a device, in
 * the phone's top bar and in the mailbox's header. Static text: it takes no focus and says nothing of its own to a screen reader beyond
 * its text.
 */
@Component({
  selector: 'app-simulated-label',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="label">{{ text }}</span>`,
  styles: `
    :host {
      display: inline-flex;
      flex: none;
    }
    .label {
      display: inline-flex;
      align-items: center;
      min-height: var(--space-5);
      padding: 0 var(--space-2);
      background: var(--simulated-label-background);
      color: var(--simulated-label-foreground);
      border: var(--simulated-label-border);
      border-radius: var(--simulated-label-radius);
      font-family: var(--font-ui);
      font-size: var(--simulated-label-typography-font-size);
      font-weight: var(--simulated-label-typography-font-weight);
      line-height: var(--simulated-label-typography-line-height);
      letter-spacing: var(--simulated-label-typography-letter-spacing);
      white-space: nowrap;
    }
  `,
})
export class SimulatedLabel {
  protected readonly text = DEVICE_TEXTS.simulated;
}
