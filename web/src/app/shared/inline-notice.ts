import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

import { Icon } from '../icon/icon';

/**
 * A short notice that sits in the flow next to what it is about: a warning or an information. It has no accent bar. With a `closeName`
 * it ends with an icon-only Close button of that name, as the banners' Close is, and a press emits `closed`; without one it has no button.
 */
@Component({
  selector: 'app-inline-notice',
  imports: [Icon],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="notice" [class.warning]="variant() === 'warning'" [class.info]="variant() === 'info'">
      <app-icon class="mark" [name]="variant() === 'warning' ? 'triangle-alert' : 'info'" [size]="16" />
      <span class="text"><ng-content /></span>
      @if (closeName(); as name) {
        <button type="button" class="button button-ghost close" [attr.aria-label]="name" (click)="closed.emit()">
          <app-icon name="x" [size]="16" />
        </button>
      }
    </div>
  `,
  styles: `
    :host {
      display: block;
    }
    .notice {
      display: flex;
      align-items: flex-start;
      gap: var(--space-2);
      padding: var(--space-2) var(--space-3);
    }
    .mark {
      margin-top: 2px;
    }
    .text {
      flex: 1;
      min-width: 0;
    }
    .close {
      flex: none;
      margin-block: calc(-1 * var(--space-2));
      padding: 0 var(--space-2);
      color: inherit;
    }
    .warning {
      background: var(--inline-notice-warning-background);
      color: var(--inline-notice-warning-foreground);
      border-radius: var(--inline-notice-warning-radius);
      font-size: var(--inline-notice-warning-typography-font-size);
      font-weight: var(--inline-notice-warning-typography-font-weight);
      line-height: var(--inline-notice-warning-typography-line-height);
    }
    .warning .mark {
      color: var(--inline-notice-warning-icon-color);
    }
    .info {
      background: var(--inline-notice-info-background);
      color: var(--inline-notice-info-foreground);
      border-radius: var(--inline-notice-info-radius);
      font-size: var(--inline-notice-info-typography-font-size);
      font-weight: var(--inline-notice-info-typography-font-weight);
      line-height: var(--inline-notice-info-typography-line-height);
    }
    .info .mark {
      color: var(--inline-notice-info-icon-color);
    }
  `,
})
export class InlineNotice {
  readonly variant = input<'warning' | 'info'>('info');
  /** The Close button's name; the notice has no Close while it is unset. */
  readonly closeName = input<string>();
  /** Emits when the Close button is pressed. */
  readonly closed = output<void>();
}
