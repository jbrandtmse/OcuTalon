import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';

import { DemoView } from '../shared/demo-view';
import { Layout } from '../shared/layout';
import { Tooltip } from '../shared/tooltip';
import { DEMO_VIEW_HELP_ID, DEMO_VIEW_TEXTS } from './demo-view-texts';

/**
 * The Demo view switch (Story 4.9): a native button with role="switch" and aria-checked, named by its label "Demo view" and described
 * by the help text, which sits in a visually hidden element outside the button. It shows only while the server's demo mode is on
 * (DemoView.available). A press (click, Space or Enter) changes the view only: nothing is sent, focus stays on the switch and the page
 * announces nothing; assistive technology hears the new state from aria-checked. In the drawer band (1024 to 1279px) the label is
 * visually hidden, still the name, and the pointer tooltip is the label; elsewhere the label shows and the tooltip is the help text.
 */
@Component({
  selector: 'app-demo-view-switch',
  imports: [Tooltip],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (demoView.available()) {
      <button
        type="button"
        role="switch"
        class="button button-ghost header-switch"
        [class.on]="demoView.switchedOn()"
        [attr.aria-checked]="demoView.switchedOn()"
        [attr.aria-describedby]="helpId"
        [appTooltip]="tooltip()"
        (click)="demoView.set(!demoView.switchedOn())"
      >
        <span class="track" aria-hidden="true"><span class="thumb"></span></span>
        <span class="label" [class.visually-hidden]="layout.band() === 'drawer'">{{ texts.label }}</span>
      </button>
      <span class="visually-hidden" [id]="helpId">{{ texts.help }}</span>
    }
  `,
  styles: `
    .header-switch {
      white-space: nowrap;
      gap: 6px;
      padding: 0 var(--space-2);
      color: var(--ink);
      font-weight: var(--type-body-strong-font-weight);
    }
    .track {
      position: relative;
      flex: none;
      box-sizing: border-box;
      display: block;
      width: 32px;
      min-height: 18px;
      border: 1px solid var(--border-strong);
      border-radius: 9px;
      background: var(--surface);
    }
    .thumb {
      position: absolute;
      top: 2px;
      left: 2px;
      width: 12px;
      min-height: 12px;
      border-radius: 50%;
      background: var(--ink-muted);
    }
    .on .track {
      border-color: var(--action);
      background: var(--action);
    }
    .on .thumb {
      left: 16px;
      background: var(--on-action);
    }
  `,
})
export class DemoViewSwitch {
  protected readonly demoView = inject(DemoView);
  protected readonly layout = inject(Layout);
  protected readonly texts = DEMO_VIEW_TEXTS;
  protected readonly helpId = DEMO_VIEW_HELP_ID;

  /** The pointer tooltip: the label where the label is hidden (drawer band), else the help text. */
  protected readonly tooltip = computed(() => (this.layout.band() === 'drawer' ? this.texts.label : this.texts.help));
}
