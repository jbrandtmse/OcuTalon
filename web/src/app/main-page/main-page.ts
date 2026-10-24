import { ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, Injector, untracked } from '@angular/core';

import { ChatPanel } from '../chat/chat-panel';
import { LiveState, LOAD_FAILED } from '../live/live-state';
import { RAIL_TEXTS } from '../rail/rail-view';
import { StatusRail } from '../rail/status-rail';
import { type FocusRule, keepFocus } from '../shared/focus-rule';
import { Popovers } from '../shared/popover';
import { ServerButton } from '../shared/server-button';

/** The labels of the rail's four list sections, in order, for the loading and failed states; the loaded rail adds its counts (Telegram is unknown until then). */
const RAIL_SECTIONS = [RAIL_TEXTS.approvals, RAIL_TEXTS.checks, RAIL_TEXTS.reminders, RAIL_TEXTS.decisions] as const;

/** The skeleton rows of each rail section while the snapshot loads. */
const SKELETON_ROWS = [1, 2] as const;

/** The id of the load error's text, which Retry is described by. */
const LOAD_ERROR_TEXT_ID = 'load-error-text';

/** Where focus goes when the load error that holds it gives way to the loaded page (UX-DR131): the main region. */
const LOAD_ERROR_RULE: FocusRule = { within: '.load-error' };

/**
 * The main page: the status rail and the chat region, under the page's one visually hidden h1. The h1 is the routed
 * page's own first element, so each later page names itself. The rail is a region named Status, 288px wide and 320px from a
 * 1440px viewport, which scrolls on its own; main follows it and takes the rest of the width.
 *
 * While the snapshot loads, both regions are aria-busy and show static skeletons, hidden from assistive technology:
 * two rows in each of the rail's four sections and three entries in main. When the load fails (no data by 10 seconds, or an error
 * answer) the rail keeps its four headings alone, and the skeletons give way to the load error at the top of main, with Retry.
 * Once it has loaded, the rail holds the status rail and main holds the chat panel after its hidden heading. When the load error
 * holds focus (its Retry button) as the page loads, focus moves to main without scrolling, through the page's focus rule
 * (shared/focus-rule.ts); a Retry that fails leaves focus where it is. Retry is described by the load error's text
 * (aria-describedby), and by its busy notice as well while that shows. The rail and main take focus (tabindex -1) but are not tab stops: the skip links
 * of the header move focus to them (Story 2.14), and each draws its focus ring inside its own edge, so that no part of it falls outside the viewport. The page's
 * data-snapshot says how the load went, and data-session-seq and data-instance-seq the last event of each stream that the page has
 * applied.
 */
@Component({
  selector: 'app-main-page',
  imports: [ChatPanel, ServerButton, StatusRail],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h1 class="visually-hidden">OcuTalon</h1>
    <section class="rail" tabindex="-1" aria-labelledby="rail-title" [attr.aria-busy]="loading() ? 'true' : null">
      <h2 id="rail-title" class="visually-hidden">Status</h2>
      @if (live.status() === 'loaded') {
        <app-status-rail />
      } @else {
        @for (label of sections; track label) {
          <h3 class="rail-heading">{{ label }}</h3>
          @if (loading()) {
            <div class="skeleton-rows" aria-hidden="true">
              @for (row of skeletonRows; track row) {
                <div class="skeleton-row">
                  <span class="skeleton row-title"></span>
                  <span class="skeleton row-detail"></span>
                  <span class="skeleton row-meta"></span>
                </div>
              }
            </div>
          }
        }
      }
    </section>
    <main
      class="main"
      tabindex="-1"
      [attr.data-snapshot]="live.status()"
      [attr.data-session-seq]="live.sessionSeq() ?? null"
      [attr.data-instance-seq]="live.instanceSeq() ?? null"
      [attr.aria-busy]="loading() ? 'true' : null"
    >
      <h2 class="visually-hidden">Chat</h2>
      @if (loading()) {
        <div class="skeleton-chat" aria-hidden="true">
          <span class="skeleton chat-bubble"></span>
          <span class="skeleton chat-text"></span>
          <span class="skeleton chat-text short"></span>
        </div>
      }
      @if (failed()) {
        <div class="load-error">
          <p class="load-error-text" [id]="loadErrorTextId">{{ loadFailed }}</p>
          <app-server-button variant="secondary" [action]="retry" [describedBy]="[loadErrorTextId]">Retry</app-server-button>
        </div>
      }
      @if (live.status() === 'loaded') {
        <app-chat-panel />
      }
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
      overflow-y: auto;
      scroll-padding: var(--space-scroll-gutter);
      width: var(--status-rail-width);
      padding: var(--space-3) var(--status-rail-padding-inline) var(--space-4);
      background: var(--status-rail-background);
      border-right: var(--status-rail-border-right);
    }
    /* The gutter is the rail's own padding; the content keeps its 12px inset with 8px of its own inside it. */
    .rail > app-status-rail,
    .rail > .rail-heading,
    .rail > .skeleton-rows {
      margin-inline: var(--space-2);
    }
    /* A focus target that is not a tab stop draws the ring and its halo inside its own edge, which is the viewport's edge. */
    .rail:focus-visible,
    .main:focus-visible {
      outline-offset: -2px;
      box-shadow: inset 0 0 0 4px var(--surface);
    }
    @media (min-width: 1440px) {
      .rail {
        width: var(--space-rail-width-wide);
      }
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
    .skeleton-rows {
      display: flex;
      flex-direction: column;
      gap: var(--space-2);
      margin-top: calc(-1 * var(--space-1));
    }
    .skeleton-row {
      display: flex;
      flex-direction: column;
      gap: 6px;
      padding: var(--space-2) var(--space-1);
    }
    .row-title {
      width: 70%;
      height: 14px;
    }
    .row-detail {
      width: 100%;
      height: 12px;
    }
    .row-meta {
      width: 40%;
      height: 10px;
    }
    .main {
      display: flex;
      flex: 1;
      flex-direction: column;
      min-width: 0;
      min-height: 0;
      background: var(--chat-panel-background);
    }
    .skeleton-chat {
      display: flex;
      flex-direction: column;
      gap: var(--space-4);
      padding: var(--space-6);
    }
    .chat-bubble {
      align-self: flex-end;
      width: 45%;
      height: 40px;
    }
    .chat-text {
      width: 80%;
      height: 16px;
    }
    .chat-text.short {
      width: 55%;
    }
    .load-error {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      gap: var(--space-3);
      padding: var(--space-6);
    }
    .load-error-text {
      margin: 0;
      color: var(--ink);
      font-size: var(--type-body-font-size);
      line-height: var(--type-body-line-height);
    }
  `,
})
export class MainPage {
  protected readonly live = inject(LiveState);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);
  private readonly injector = inject(Injector);
  private readonly popovers = inject(Popovers);
  protected readonly sections = RAIL_SECTIONS;
  protected readonly skeletonRows = SKELETON_ROWS;
  protected readonly loadFailed = LOAD_FAILED;
  protected readonly loadErrorTextId = LOAD_ERROR_TEXT_ID;
  protected readonly loading = computed(() => this.live.status() === 'loading');
  protected readonly failed = computed(() => this.live.status() === 'failed');

  /** The Retry button's call: asks for the snapshot again and settles when it answers. */
  protected readonly retry = () => this.live.retry();

  constructor() {
    effect(() => {
      this.live.status();
      untracked(() => keepFocus(this.host.nativeElement, this.injector, this.popovers, LOAD_ERROR_RULE));
    });
  }
}
