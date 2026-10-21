import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/** The icons the page uses: Lucide paths (ISC), drawn on a 24 grid. */
export type IconName = 'chevron-down' | 'circle-alert' | 'eye';

@Component({
  selector: 'app-icon',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <svg
      class="icon"
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      @switch (name()) {
        @case ('chevron-down') {
          <path d="m6 9 6 6 6-6" />
        }
        @case ('circle-alert') {
          <circle cx="12" cy="12" r="10" />
          <line x1="12" x2="12" y1="8" y2="12" />
          <line x1="12" x2="12.01" y1="16" y2="16" />
        }
        @case ('eye') {
          <path
            d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"
          />
          <circle cx="12" cy="12" r="3" />
        }
      }
    </svg>
  `,
  styles: `
    :host {
      display: inline-flex;
    }
    .icon {
      width: 14px;
      height: 14px;
      flex: none;
    }
  `,
})
export class Icon {
  readonly name = input.required<IconName>();
}
