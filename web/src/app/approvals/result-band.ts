import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { Icon } from '../icon/icon';
import { IncidentDismiss, type DismissTarget } from '../incidents/incident-dismiss';
import type { ResultView } from './approval-view';

/**
 * The result band of one request (Story 6.4; FR-8, UX-DR79): `result-success` with `circle-check` for a full success, `result-partial`
 * with `triangle-alert` or `clock` for the rest (approval-view.ts resultView), on the result tokens. It holds the icon, the text and,
 * when `dismiss` is set, Dismiss at its right end (the last request's band of a resolved or open incident); "Recorded in the IRIS audit
 * log." follows beneath the band in caption. It is not a live region (the chat announces a result, once) and moves no focus. Every
 * text is bound by interpolation, never as markup.
 */
@Component({
  selector: 'app-result-band',
  imports: [Icon, IncidentDismiss],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div [class]="'band tone-' + result().tone" data-part="result" [attr.data-tone]="result().tone">
      <app-icon [name]="result().icon" [size]="16" />
      <span class="text">{{ result().text }}</span>
      @if (dismiss(); as target) {
        <app-incident-dismiss class="dismiss" [target]="target" />
      }
    </div>
    <p class="audit">{{ result().audit }}</p>
  `,
  styles: `
    :host {
      display: block;
      margin-top: var(--space-1);
    }
    .band {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
      padding: var(--space-1) var(--space-3);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .tone-success {
      background: var(--result-success-background);
      color: var(--result-success-foreground);
      border-radius: var(--result-success-radius);
    }
    .tone-partial {
      background: var(--result-partial-background);
      color: var(--result-partial-foreground);
      border-radius: var(--result-partial-radius);
    }
    .text {
      flex: 1 1 12rem;
      min-width: 0;
      overflow-wrap: anywhere;
    }
    .dismiss {
      margin-inline-start: auto;
    }
    .audit {
      margin: 0;
      padding-inline: var(--space-3);
      color: var(--ink-muted);
      font-size: var(--type-caption-font-size);
      font-weight: var(--type-caption-font-weight);
      line-height: var(--type-caption-line-height);
    }
  `,
})
export class ResultBand {
  /** The band: its text, tone, icon and audit line. */
  readonly result = input.required<ResultView>();
  /** The Dismiss at the band's right end; undefined for none. */
  readonly dismiss = input<DismissTarget | undefined>(undefined);
}
