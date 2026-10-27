import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { TraceLink } from '../shared/trace-link';
import { INCIDENT_TEXTS, type PanelView } from './incident-view';

/**
 * The evidence panel (UX-DR78, FR-24) of an incident card, below its Show details row: here, and only here, error text and item
 * names appear as IRIS shows them. Each row of the view is a label in the page's UI font over its value lines, which are in
 * mono-sm where the view says so; while a request is pending the note says the request is held as an IRIS Workflow task; the
 * links are the served trace URLs, each named by its own text. Every text is bound by interpolation, never as markup. The panel
 * is not a live region and moves no focus.
 */
@Component({
  selector: 'app-evidence-panel',
  imports: [TraceLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="panel">
      @for (row of panel().rows; track row.label) {
        <div class="row">
          <div class="label">{{ row.label }}</div>
          @for (line of row.lines; track $index) {
            <div class="value" [class.mono]="row.mono">{{ line }}</div>
          }
        </div>
      }
      @if (panel().held) {
        <p class="held">{{ texts.held }}</p>
      }
      @if (panel().links.length > 0) {
        <div class="links">
          @for (link of panel().links; track link.text) {
            <app-trace-link [url]="link.url" [text]="link.text" />
          }
        </div>
      }
    </div>
  `,
  styles: `
    :host {
      display: block;
    }
    .panel {
      display: flex;
      flex-direction: column;
      gap: var(--space-3);
      padding: var(--space-3);
      background: var(--evidence-panel-background);
      border-radius: var(--evidence-panel-radius);
      color: var(--ink);
    }
    .label {
      color: var(--ink-muted);
      font-family: var(--font-ui);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: var(--type-label-line-height);
    }
    .value {
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
      overflow-wrap: anywhere;
    }
    .value.mono {
      font-family: var(--font-mono);
      font-size: var(--evidence-panel-typography-font-size);
      font-weight: var(--evidence-panel-typography-font-weight);
      line-height: var(--evidence-panel-typography-line-height);
    }
    .held {
      margin: 0;
      font-size: var(--type-body-sm-font-size);
      line-height: var(--type-body-sm-line-height);
    }
    .links {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-4);
    }
  `,
})
export class EvidencePanel {
  readonly panel = input.required<PanelView>();
  protected readonly texts = INCIDENT_TEXTS;
}
