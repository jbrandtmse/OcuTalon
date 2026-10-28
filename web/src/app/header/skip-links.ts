import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';

import { LiveState } from '../live/live-state';
import { Layout } from '../shared/layout';

/** A skip link: its text, the selector of the region it moves focus to, and whether it shows only in demo mode. */
export interface SkipLink {
  text: string;
  target: string;
  demo?: boolean;
}

/**
 * The skip links in tab order (UX: Skip to chat, Skip to simulated devices in demo mode, Skip to status). The targets are the page's own
 * regions: main takes focus without being a tab stop (tabindex -1), the simulated devices region takes it the same way (tabindex -1),
 * and the rail is one only while it scrolls on its own (tabindex -1 when stacked). A later story adds its link here, in the place the UX gives it.
 */
export const SKIP_LINKS: readonly SkipLink[] = [
  { text: 'Skip to chat', target: 'main.main' },
  { text: 'Skip to simulated devices', target: 'app-device-panel section', demo: true },
  { text: 'Skip to status', target: 'section.rail' },
];

/**
 * The skip links (Story 2.14; NFR-25, UX-DR11): the first tab stops of the page, before the header. Each is a link with the
 * page's own address (href="#/"), so a middle-click opens the same page; a press, by click or by Enter, never follows it. It moves
 * focus to the region through Layout.focusRegion, which is the user's own move: "Skip to status" opens a closed drawer first (Story
 * 2.15). It does nothing when the page has no such region. The link to the simulated devices exists only while demo mode is on. A skip link is visually
 * hidden until it has focus; with focus it shows at the top left of the page, above the header, with the text link's look and its
 * focus ring inside the viewport. The component is no landmark: it renders no nav.
 */
@Component({
  selector: 'app-skip-links',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (link of links(); track link.target) {
      <a class="link skip-link" href="#/" (click)="skip($event, link.target)">{{ link.text }}</a>
    }
  `,
  styles: `
    :host {
      display: contents;
    }
    .skip-link {
      position: fixed;
      top: var(--space-2);
      left: var(--space-2);
      z-index: 2;
      display: inline-flex;
      align-items: center;
      min-height: var(--space-target-min);
      padding: 0 var(--space-3);
      border-radius: var(--rounded-sm);
      background: var(--surface);
      white-space: nowrap;
    }
    .skip-link:not(:focus) {
      overflow: hidden;
      clip-path: inset(50%);
    }
  `,
})
export class SkipLinks {
  private readonly layout = inject(Layout);
  private readonly live = inject(LiveState);

  /** The links that show: the demo-only link only while the snapshot says demo mode is on. */
  protected readonly links = computed(() => SKIP_LINKS.filter((link) => link.demo !== true || this.live.snapshot()?.demoMode === true));

  /** Moves focus to the region (opening the drawer that holds it) and keeps the press from following the link. */
  protected skip(event: Event, target: string): void {
    event.preventDefault();
    this.layout.focusRegion(target);
  }
}
