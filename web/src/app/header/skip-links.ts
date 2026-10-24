import { ChangeDetectionStrategy, Component, DOCUMENT, inject } from '@angular/core';

/** A skip link: its text and the selector of the region it moves focus to. */
export interface SkipLink {
  text: string;
  target: string;
}

/**
 * The skip links in tab order (UX: Skip to chat, Skip to status). The targets are the page's own regions, which take focus without
 * being tab stops (tabindex -1). A later story adds its link here, in the place the UX gives it.
 */
export const SKIP_LINKS: readonly SkipLink[] = [
  { text: 'Skip to chat', target: 'main.main' },
  { text: 'Skip to status', target: 'section.rail' },
];

/**
 * The skip links (Story 2.14; NFR-25, UX-DR11): the first tab stops of the page, before the header. Each is a link with the
 * page's own address (href="#/"), so a middle-click opens the same page; a press, by click or by Enter, never follows it. It moves
 * focus to the region, which is the user's own move, and does nothing when the page has no such region. A skip link is visually
 * hidden until it has focus; with focus it shows at the top left of the page, above the header, with the text link's look and its
 * focus ring inside the viewport. The component is no landmark: it renders no nav.
 */
@Component({
  selector: 'app-skip-links',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (link of links; track link.target) {
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
      z-index: 1;
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
  private readonly document = inject(DOCUMENT);
  protected readonly links = SKIP_LINKS;

  /** Moves focus to the region and keeps the press from following the link. */
  protected skip(event: Event, target: string): void {
    event.preventDefault();
    this.document.querySelector<HTMLElement>(target)?.focus();
  }
}
