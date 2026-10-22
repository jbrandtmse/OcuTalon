import { ChangeDetectionStrategy, Component, inject } from '@angular/core';

import { LiveState } from '../live/live-state';

/** The labels of the rail's sections, in order. The sections' rows and counts arrive with their own stories. */
const RAIL_SECTIONS = ['Approval requests', 'Background checks', 'Reminders', 'Recent decisions'] as const;

/**
 * The main page: the status rail and the chat region, under the page's one visually hidden h1. The h1 is the routed
 * page's own first element, so each later page names itself. The rail is a region named Status; main follows it and
 * takes the rest of the width. The page's data-snapshot says how the snapshot's load went.
 */
@Component({
  selector: 'app-main-page',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h1 class="visually-hidden">OcuTalon</h1>
    <section class="rail" aria-labelledby="rail-title">
      <h2 id="rail-title" class="visually-hidden">Status</h2>
      @for (label of sections; track label) {
        <h3 class="rail-heading">{{ label }}</h3>
      }
    </section>
    <main class="main" [attr.data-snapshot]="live.status()">
      <h2 class="visually-hidden">Chat</h2>
    </main>
  `,
  styles: `
    :host {
      display: flex;
      flex: 1;
      min-height: 0;
    }
    .rail {
      flex: none;
      display: flex;
      flex-direction: column;
      gap: 14px;
      width: var(--status-rail-width);
      padding: var(--space-3) var(--space-3) var(--space-4);
      background: var(--status-rail-background);
      border-right: var(--status-rail-border-right);
    }
    .rail-heading {
      margin: 0;
      color: var(--status-rail-section-heading-color);
      font-size: var(--status-rail-section-heading-font-size);
      font-weight: var(--status-rail-section-heading-font-weight);
      line-height: var(--status-rail-section-heading-line-height);
      letter-spacing: var(--status-rail-section-heading-letter-spacing);
      text-transform: uppercase;
    }
    .main {
      flex: 1;
      min-width: 0;
      background: var(--chat-panel-background);
    }
  `,
})
export class MainPage {
  protected readonly live = inject(LiveState);
  protected readonly sections = RAIL_SECTIONS;
}
