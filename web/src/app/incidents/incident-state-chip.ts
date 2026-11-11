import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import type { IncidentChip } from './incident-view';

/**
 * The incident state chip (UX-DR72; Stories 6.1 and 25.2): a static pill with the state's text, coloured by the incident-state tokens of its
 * `chip`. The incident card and the History page's incident rows both draw it. It is not focusable and holds only the text it is given.
 */
@Component({
  selector: 'app-incident-state-chip',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span [class]="'chip chip-' + chip()">{{ text() }}</span>`,
  styles: `
    :host {
      display: contents;
    }
    .chip {
      display: inline-flex;
      align-items: center;
      min-height: 22px;
      padding: 0 var(--space-2);
      border-radius: var(--rounded-full);
      font-size: var(--type-label-font-size);
      font-weight: var(--type-label-font-weight);
      line-height: 1;
      white-space: nowrap;
    }
    .chip-open {
      background: var(--incident-state-open-background);
      color: var(--incident-state-open-foreground);
    }
    .chip-awaiting-approval {
      background: var(--incident-state-awaiting-approval-background);
      color: var(--incident-state-awaiting-approval-foreground);
    }
    .chip-fixing {
      background: var(--incident-state-fixing-background);
      color: var(--incident-state-fixing-foreground);
    }
    .chip-resolved {
      background: var(--incident-state-resolved-background);
      color: var(--incident-state-resolved-foreground);
    }
    .chip-closed {
      background: var(--incident-state-closed-background);
      color: var(--incident-state-closed-foreground);
    }
  `,
})
export class IncidentStateChip {
  /** The state's chip name, which picks the colours. */
  readonly chip = input.required<IncidentChip | undefined>();
  /** The state's text, as incident-view.stateText gives it. */
  readonly text = input.required<string>();
}
