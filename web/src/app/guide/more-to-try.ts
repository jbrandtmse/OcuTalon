import { afterNextRender, ChangeDetectionStrategy, Component, computed, inject, Injector, input, output } from '@angular/core';
import { RouterLink } from '@angular/router';

import { ChatOutbox } from '../chat/chat-outbox';
import { COMPOSER_REASON_ID } from '../chat/composer';
import { turnInFlight } from '../chat/try-it-view';
import { DeviceTabs } from '../devices/device-tabs';
import { AllowanceState } from '../live/allowance-state';
import { LiveState } from '../live/live-state';
import { chipName, SAMPLES } from '../mailbox/mailbox-view';
import { PERSONA_HEADING_ID } from '../rail/persona-card/persona-card-view';
import { Layout, RAIL_REGION } from '../shared/layout';
import { HEIGHT_QUERIES, LAYOUT_QUERIES } from '../shared/layout-view';
import { BREAK_FEED_BUTTON, MORE_TO_TRY_TEXTS, type MoreToTryItem } from './more-to-try-view';

/** The Persona card's Change button. */
const PERSONA_CHANGE = 'app-persona-card button.change';

/** The suspicious-request chip of the Simulated mailbox, found by its own name. */
const SUSPICIOUS_CHIP = `app-simulated-mailbox button[aria-label="${chipName(SAMPLES[2].label)}"]`;

/** The header's Demo view switch. */
const DEMO_VIEW_SWITCH = 'app-demo-view-switch [role="switch"]';

/** The count that gives each panel its own label id. */
let panels = 0;

/**
 * The "Other things to try" panel of the demo guide (Story 4.11; EXPERIENCE: Demo guide and controls): a labelled group, never a
 * heading, with one list item for each item it is given (more-to-try-view.ts itemsFor): the label, the look-for line and one native
 * control named by its visible text. It decides nothing about which items show; the guide gives it the server's.
 *
 * A control hands off to the control the page already has: it puts focus on that control and presses it, so the action is exactly that
 * control's own. Item 1 opens the rail and the Persona card's Change, item 2 selects the Simulated mailbox tab and presses the
 * suspicious-request chip, item 3 presses the box's Break the feed, item 4 presses the Demo view switch while it is on, item 5 sends its
 * prompt through the chat's outbox (a new message of the user's), item 6 is a link to the Documents page and item 7 opens the rail. Every
 * action runs from the control's own click, and focus moves only for that press. The panel announces nothing, and it emits `pressed` so
 * that the guide keeps the panel open.
 *
 * Where the page fills the viewport (LAYOUT_QUERIES.framed) the group is a vertical scroll region of its own, a Tab stop named by the panel
 * label (the project's rule for a scroller), and its height is the viewport's height less a fixed reserve for the page's other parts and
 * the chat's minimum (never less than the label's line, the gap under it and one control), so the chat keeps its room and the page does
 * not scroll as a whole; the items lay out in as many columns as fit, and the list ends in a gutter that holds the last control's ring. The group carries the focus rule's `moreItem` key like the controls, so a focused group hands
 * focus on when the finish leaves.
 * In the stacked column the page scrolls and the group grows with its items.
 *
 * Item 5 is aria-disabled, never disabled, while a turn is in flight or the message allowance is used up, and a press then sends nothing.
 */
@Component({
  selector: 'app-more-to-try',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="group ring-inside" role="group" tabindex="0" data-guide-focus="moreItem" [attr.aria-labelledby]="labelId">
      <p class="group-label" [id]="labelId">{{ texts.label }}</p>
      <ul class="items">
        @for (item of items(); track item.id) {
          <li class="item">
            <p class="item-label">{{ item.label }}</p>
            <p class="look-for">{{ item.lookFor }}</p>
            @if (item.action === 'documents') {
              <a class="button button-secondary" routerLink="/documents" data-guide-focus="moreItem" (click)="pressed.emit()">{{ item.button }}</a>
            } @else {
              <button
                type="button"
                class="button button-secondary"
                data-guide-focus="moreItem"
                [attr.aria-disabled]="item.action === 'memory' && blocked() ? 'true' : null"
                [attr.aria-describedby]="item.action === 'memory' ? describedBy() : null"
                (click)="press(item)"
              >{{ item.button }}</button>
            }
          </li>
        }
      </ul>
    </div>
  `,
  styles: `
    :host {
      display: block;
      margin-top: var(--space-1);
      --more-label-height: calc(var(--type-body-sm-font-size) * var(--type-body-sm-line-height));
      --more-gap: var(--space-1);
      --more-window-min: calc(var(--more-label-height) + var(--more-gap) + var(--space-control-height));
      --more-reserve: 685px;
    }
    @media ${HEIGHT_QUERIES.compact} and ${LAYOUT_QUERIES.framed} {
      :host {
        --more-reserve: 592px;
        --more-gap: 0px;
        margin-top: 0;
      }
    }
    .group {
      display: flex;
      flex-direction: column;
      align-items: stretch;
      gap: var(--more-gap);
      padding-inline: var(--space-1);
    }
    .group-label {
      margin: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .items {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(min(20rem, 100%), 1fr));
      gap: var(--space-2) var(--space-4);
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .item {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--space-2);
    }
    .item p {
      margin: 0;
    }
    .item-label {
      flex: 1 1 100%;
      color: var(--ink);
      font-size: var(--type-body-font-size);
      font-weight: var(--type-body-strong-font-weight);
      line-height: var(--type-body-line-height);
    }
    .look-for {
      flex: 1 1 20rem;
      min-width: 0;
      color: var(--ink-muted);
      font-size: var(--type-body-sm-font-size);
      font-weight: var(--type-body-sm-font-weight);
      line-height: var(--type-body-sm-line-height);
    }
    .item .button {
      flex: none;
    }
    /* Where the page fills the viewport, the panel is a scroll region of its own: it leaves the chat the room it needs, so the page
       never scrolls as a whole. The reserve is the height that the rest of the page needs (header, rail and chat chrome, the guide
       without the panel and the chat's own minimum). The window never gets shorter than the label's line, the gap under it and one
       control, so the label and a whole control show together and every control scrolls fully into view; the list's end gutter lets
       the last control scroll clear of the edge, so its focus ring is never clipped. */
    @media ${LAYOUT_QUERIES.framed} {
      .group {
        overflow-y: auto;
        scroll-padding: var(--space-scroll-gutter);
        max-height: max(var(--more-window-min), calc(100vh - var(--more-reserve)));
        max-height: max(var(--more-window-min), calc(100dvh - var(--more-reserve)));
      }
      .items {
        padding-block-end: var(--space-scroll-gutter);
      }
    }
  `,
})
export class MoreToTry {
  private readonly layout = inject(Layout);
  private readonly tabs = inject(DeviceTabs);
  private readonly outbox = inject(ChatOutbox);
  private readonly live = inject(LiveState);
  private readonly allowance = inject(AllowanceState);
  private readonly injector = inject(Injector);

  /** The items to show, in the order to show them. */
  readonly items = input.required<readonly MoreToTryItem[]>();

  /** A control was pressed: the guide keeps the panel open. */
  readonly pressed = output<void>();

  protected readonly texts = MORE_TO_TRY_TEXTS;
  protected readonly labelId = `more-to-try-label-${++panels}`;

  /** True while the session's message allowance is used up. */
  private readonly used = computed(() => this.allowance.active() !== undefined);

  /** True while the memory item's press sends nothing: a turn is in flight (turnInFlight) or the allowance is used up. */
  protected readonly blocked = computed(() => this.used() || turnInFlight(this.live.store()?.chat ?? [], this.outbox.entries()));

  /** The composer's reason, while the allowance is used up; else none. */
  protected readonly describedBy = computed(() => (this.used() ? COMPOSER_REASON_ID : null));

  /** The user pressed an item's button: its hand-off. */
  protected press(item: MoreToTryItem): void {
    this.pressed.emit();
    switch (item.action) {
      case 'persona':
        this.layout.focusRegion(RAIL_REGION);
        this.handTo([PERSONA_CHANGE, `#${PERSONA_HEADING_ID}`], (control) => control.getAttribute('aria-expanded') !== 'true');
        break;
      case 'suspiciousEmail':
        this.tabs.select('mailbox');
        this.handTo([SUSPICIOUS_CHIP], () => true);
        break;
      case 'rejectFix':
        this.handTo([BREAK_FEED_BUTTON], () => true);
        break;
      case 'demoView':
        this.handTo([DEMO_VIEW_SWITCH], (control) => control.getAttribute('aria-checked') === 'true');
        break;
      case 'memory':
        if (!this.blocked()) {
          this.outbox.send(MORE_TO_TRY_TEXTS.rememberPrompt);
        }
        break;
      case 'heartbeat':
        this.layout.focusRegion(RAIL_REGION);
        break;
      default:
        break;
    }
  }

  /** After the next render, focuses the first control found and presses it when `press` says so: the control's own action runs. */
  private handTo(selectors: readonly string[], press: (control: HTMLElement) => boolean): void {
    afterNextRender(
      () => {
        for (const selector of selectors) {
          const control = document.querySelector<HTMLElement>(selector);
          if (control !== null) {
            control.focus();
            if (press(control)) {
              control.click();
            }
            return;
          }
        }
      },
      { injector: this.injector },
    );
  }
}
