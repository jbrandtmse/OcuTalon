import { ChangeDetectionStrategy, Component } from '@angular/core';

import { Icon } from '../icon/icon';
import { DECISION_TEXTS } from './decision-view';

/**
 * The fallback flag (UX-DR64): an amber pill with a life-buoy icon (hidden from assistive technology) and the word "Fallback". It
 * sits beside the outcome chip of every fallback decision (FR-4), and later beside the state chip of an incident card. It is not
 * focusable and carries no tooltip.
 */
@Component({
  selector: 'app-fallback-flag',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="flag"><app-icon name="life-buoy" [size]="12" />{{ text }}</span>`,
  styles: `
    :host {
      display: inline-flex;
    }
    .flag {
      display: inline-flex;
      align-items: center;
      gap: var(--space-1);
      height: 22px;
      padding: 0 var(--space-2) 0 6px;
      background: var(--fallback-flag-background);
      color: var(--fallback-flag-foreground);
      border-radius: var(--fallback-flag-radius);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: 1;
      white-space: nowrap;
    }
  `,
})
export class FallbackFlag {
  protected readonly text = DECISION_TEXTS.fallbackFlag;
}
